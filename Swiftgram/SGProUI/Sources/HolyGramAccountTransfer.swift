// MARK: HolyGram: move accounts between devices with a password-protected file
import Foundation
import UIKit
import UniformTypeIdentifiers
import CryptoKit
import CommonCrypto
import SwiftSignalKit
import TelegramCore
import AccountContext
import SGLogging

enum HolyGramAccountTransferError: Error {
    case wrongFormat
    case wrongPassword
    case keyDerivationFailed
}

/// File layout: magic (8 bytes) | salt (16 bytes) | AES-256-GCM combined box (nonce | ciphertext | tag).
/// The key is PBKDF2-HMAC-SHA256 of the password. The plaintext is a JSON array of `SessionBackup`.
enum HolyGramAccountTransferFile {
    static let fileExtension = "holygram"
    private static let magic = Data("HGACCT01".utf8)
    private static let saltLength = 16
    private static let iterations: UInt32 = 310_000

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derived = Data(repeating: 0, count: 32)
        let status = derived.withUnsafeMutableBytes { derivedBytes -> Int32 in
            return salt.withUnsafeBytes { saltBytes -> Int32 in
                return passwordData.withUnsafeBytes { passwordBytes -> Int32 in
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        if status != Int32(kCCSuccess) {
            throw HolyGramAccountTransferError.keyDerivationFailed
        }
        return SymmetricKey(data: derived)
    }

    static func encrypt(_ backups: [SessionBackup], password: String) throws -> Data {
        let plaintext = try JSONEncoder().encode(backups)
        var salt = Data(repeating: 0, count: saltLength)
        let saltStatus = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!) }
        if saltStatus != errSecSuccess {
            throw HolyGramAccountTransferError.keyDerivationFailed
        }
        let key = try deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw HolyGramAccountTransferError.wrongFormat
        }
        return magic + salt + combined
    }

    static func decrypt(_ data: Data, password: String) throws -> [SessionBackup] {
        guard data.count > magic.count + saltLength, data.prefix(magic.count) == magic else {
            throw HolyGramAccountTransferError.wrongFormat
        }
        let salt = data.subdata(in: magic.count ..< magic.count + saltLength)
        let combined = data.subdata(in: magic.count + saltLength ..< data.count)
        let key = try deriveKey(password: password, salt: salt)
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(try AES.GCM.SealedBox(combined: combined), using: key)
        } catch {
            throw HolyGramAccountTransferError.wrongPassword
        }
        return try JSONDecoder().decode([SessionBackup].self, from: plaintext)
    }
}

/// Adds the given sessions to the account manager, skipping accounts already on this device.
/// Calls `completion` on the main queue with the number of accounts added.
func holyGramImportSessionBackups(_ backups: [SessionBackup], context: AccountContext, completion: @escaping (Int) -> Void) {
    let _ = (context.sharedContext.accountManager.accountRecords()
    |> take(1)
    |> deliverOnMainQueue).start(next: { view in
        var existingPeerIds = Set<Int64>()
        for record in view.records {
            for attribute in record.attributes {
                if case let .backupData(backupData) = attribute, let peerId = backupData.data?.peerId {
                    existingPeerIds.insert(peerId)
                }
            }
        }
        let toImport = backups.filter { $0.peerIdInternal != 0 && !existingPeerIds.contains($0.peerIdInternal) }
        if toImport.isEmpty {
            completion(0)
            return
        }
        let _ = (context.sharedContext.accountManager.transaction { transaction -> Int in
            var nextSortOrder = (transaction.getRecords().map({ record -> Int32 in
                for attribute in record.attributes {
                    if case let .sortOrder(sortOrder) = attribute {
                        return sortOrder.order
                    }
                }
                return 0
            }).max() ?? 0) + 1
            for backup in toImport {
                var attributes = backup.accountRecord.attributes
                attributes.removeAll { attribute in
                    if case .sortOrder = attribute {
                        return true
                    }
                    return false
                }
                attributes.append(.sortOrder(AccountSortOrderAttribute(order: nextSortOrder)))
                nextSortOrder += 1
                let id = transaction.createRecord(attributes)
                SGLogger.shared.log("AccountTransfer", "Imported record \(id) for \(backup.userId)")
            }
            return toImport.count
        }
        |> deliverOnMainQueue).start(next: { count in
            completion(count)
        })
    })
}

/// Current logged-in accounts as `SessionBackup`s, named like the keychain backup does.
func holyGramCurrentSessionBackups(context: AccountContext, completion: @escaping ([SessionBackup]) -> Void) {
    let _ = (combineLatest(
        context.sharedContext.accountManager.accountRecords() |> take(1),
        context.sharedContext.activeAccountsWithInfo |> take(1)
    )
    |> deliverOnMainQueue).start(next: { view, accountsWithInfo in
        var result: [SessionBackup] = []
        for record in view.records {
            var isLoggedOut = false
            var peerId: Int64 = 0
            for attribute in record.attributes {
                if case .loggedOut = attribute {
                    isLoggedOut = true
                } else if case let .backupData(backupData) = attribute {
                    peerId = backupData.data?.peerId ?? 0
                }
            }
            if isLoggedOut || peerId == 0 {
                continue
            }
            var name: String?
            if let info = accountsWithInfo.1.first(where: { $0.peer.id == EnginePeer.Id(peerId) }) {
                if let username = info.peer.addressName {
                    name = "@\(username)"
                } else {
                    name = info.peer.debugDisplayTitle
                }
            }
            result.append(SessionBackup(name: name, accountRecord: record))
        }
        completion(result)
    })
}

/// Drives the export and import flows with plain UIKit alerts, pickers and share sheets.
final class HolyGramAccountTransferCoordinator: NSObject, UIDocumentPickerDelegate {
    nonisolated(unsafe) private static var current: HolyGramAccountTransferCoordinator?

    private let context: AccountContext
    private let lang: String
    private weak var presenter: UIViewController?
    private let onImported: () -> Void

    private var isRussian: Bool {
        return self.lang.hasPrefix("ru") || self.lang.hasPrefix("uk")
    }

    private func t(_ ru: String, _ en: String) -> String {
        return self.isRussian ? ru : en
    }

    private init(context: AccountContext, lang: String, presenter: UIViewController, onImported: @escaping () -> Void) {
        self.context = context
        self.lang = lang
        self.presenter = presenter
        self.onImported = onImported
    }

    static func topViewController(from view: UIView?) -> UIViewController? {
        guard var top = view?.window?.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: Export

    static func startExport(context: AccountContext, lang: String, from view: UIView?) {
        guard let presenter = topViewController(from: view) else {
            return
        }
        let coordinator = HolyGramAccountTransferCoordinator(context: context, lang: lang, presenter: presenter, onImported: {})
        HolyGramAccountTransferCoordinator.current = coordinator
        coordinator.askExportPassword()
    }

    private func askExportPassword() {
        let alert = UIAlertController(
            title: t("Экспорт аккаунтов", "Export Accounts"),
            message: t("Файл даёт полный доступ ко всем вашим аккаунтам. Придумайте надёжный пароль — без него файл не открыть.", "The file gives full access to all your accounts. Choose a strong password; the file can't be opened without it."),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = self.t("Пароль (от 6 символов)", "Password (6+ characters)")
        }
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = self.t("Повторите пароль", "Repeat password")
        }
        alert.addAction(UIAlertAction(title: t("Отмена", "Cancel"), style: .cancel, handler: { _ in
            HolyGramAccountTransferCoordinator.current = nil
        }))
        alert.addAction(UIAlertAction(title: t("Экспорт", "Export"), style: .default, handler: { [weak alert] _ in
            let password = alert?.textFields?[0].text ?? ""
            let repeated = alert?.textFields?[1].text ?? ""
            if password.count < 6 || password != repeated {
                self.showMessage(title: self.t("Пароль не подходит", "Invalid password"), text: self.t("Пароль должен быть не короче 6 символов, и оба поля должны совпадать.", "The password must be at least 6 characters and both fields must match."), done: {
                    self.askExportPassword()
                })
                return
            }
            self.export(password: password)
        }))
        self.presenter?.present(alert, animated: true)
    }

    private func export(password: String) {
        holyGramCurrentSessionBackups(context: self.context, completion: { backups in
            if backups.isEmpty {
                self.showMessage(title: self.t("Нет аккаунтов", "No accounts"), text: self.t("Нечего экспортировать.", "There is nothing to export."), done: nil)
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<URL, Error>
                do {
                    let data = try HolyGramAccountTransferFile.encrypt(backups, password: password)
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("HolyGram-accounts-\(formatter.string(from: Date())).\(HolyGramAccountTransferFile.fileExtension)")
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                    result = .success(url)
                } catch {
                    result = .failure(error)
                }
                DispatchQueue.main.async {
                    switch result {
                    case let .success(url):
                        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        share.completionWithItemsHandler = { _, _, _, _ in
                            try? FileManager.default.removeItem(at: url)
                            HolyGramAccountTransferCoordinator.current = nil
                        }
                        if let popover = share.popoverPresentationController, let view = self.presenter?.view {
                            popover.sourceView = view
                            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
                        }
                        self.presenter?.present(share, animated: true)
                    case let .failure(error):
                        SGLogger.shared.log("AccountTransfer", "Export failed: \(error)")
                        self.showMessage(title: self.t("Ошибка", "Error"), text: self.t("Не удалось создать файл.", "Couldn't create the file."), done: nil)
                    }
                }
            }
        })
    }

    // MARK: Import

    static func startImport(context: AccountContext, lang: String, from view: UIView?, onImported: @escaping () -> Void) {
        guard let presenter = topViewController(from: view) else {
            return
        }
        let coordinator = HolyGramAccountTransferCoordinator(context: context, lang: lang, presenter: presenter, onImported: onImported)
        HolyGramAccountTransferCoordinator.current = coordinator
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .item], asCopy: true)
        picker.delegate = coordinator
        picker.allowsMultipleSelection = false
        presenter.present(picker, animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        HolyGramAccountTransferCoordinator.current = nil
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            HolyGramAccountTransferCoordinator.current = nil
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if accessing {
            url.stopAccessingSecurityScopedResource()
        }
        guard let data else {
            self.showMessage(title: self.t("Ошибка", "Error"), text: self.t("Не удалось прочитать файл.", "Couldn't read the file."), done: {
                HolyGramAccountTransferCoordinator.current = nil
            })
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.askImportPassword(data: data)
        }
    }

    private func askImportPassword(data: Data) {
        let alert = UIAlertController(
            title: t("Импорт аккаунтов", "Import Accounts"),
            message: t("Введите пароль, который вы задали при экспорте.", "Enter the password you set when exporting."),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = self.t("Пароль", "Password")
        }
        alert.addAction(UIAlertAction(title: t("Отмена", "Cancel"), style: .cancel, handler: { _ in
            HolyGramAccountTransferCoordinator.current = nil
        }))
        alert.addAction(UIAlertAction(title: t("Импорт", "Import"), style: .default, handler: { [weak alert] _ in
            let password = alert?.textFields?.first?.text ?? ""
            self.importData(data, password: password)
        }))
        self.presenter?.present(alert, animated: true)
    }

    private func importData(_ data: Data, password: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<[SessionBackup], Error>
            do {
                result = .success(try HolyGramAccountTransferFile.decrypt(data, password: password))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                switch result {
                case let .success(backups):
                    holyGramImportSessionBackups(backups, context: self.context, completion: { count in
                        let text: String
                        if count == 0 {
                            text = self.t("Все аккаунты из файла уже есть на этом устройстве.", "All accounts from the file are already on this device.")
                        } else {
                            text = self.t("Добавлено аккаунтов: \(count). Чтобы избежать конфликтов, удалите их из HolyGram на старом устройстве (в списке бэкапов: удерживайте аккаунт → «Удалить из приложения»).", "Accounts added: \(count). To avoid conflicts, remove them from HolyGram on the old device (in the backup list, long-press an account → Remove from App).")
                        }
                        self.onImported()
                        self.showMessage(title: self.t("Готово", "Done"), text: text, done: {
                            HolyGramAccountTransferCoordinator.current = nil
                        })
                    })
                case let .failure(error):
                    let text: String
                    switch error as? HolyGramAccountTransferError {
                    case .wrongPassword:
                        text = self.t("Неверный пароль.", "Wrong password.")
                    case .wrongFormat:
                        text = self.t("Это не файл аккаунтов HolyGram.", "This isn't a HolyGram accounts file.")
                    default:
                        text = self.t("Не удалось открыть файл.", "Couldn't open the file.")
                    }
                    self.showMessage(title: self.t("Ошибка", "Error"), text: text, done: {
                        if case .wrongPassword? = error as? HolyGramAccountTransferError {
                            self.askImportPassword(data: data)
                        } else {
                            HolyGramAccountTransferCoordinator.current = nil
                        }
                    })
                }
            }
        }
    }

    // MARK: Helpers

    private func showMessage(title: String, text: String, done: (() -> Void)?) {
        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            done?()
        }))
        self.presenter?.present(alert, animated: true)
    }
}
