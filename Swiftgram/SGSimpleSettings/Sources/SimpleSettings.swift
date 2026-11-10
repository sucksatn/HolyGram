import Foundation
import SGAppGroupIdentifier
import SGLogging

let APP_GROUP_IDENTIFIER = sgAppGroupIdentifier()

public class SGSimpleSettings {
    
    public static let shared = SGSimpleSettings()
    
    private init() {
        setDefaultValues()
        migrate()
        preCacheValues()
    }
    
    private func setDefaultValues() {
        UserDefaults.standard.register(defaults: SGSimpleSettings.defaultValues)
        // Just in case group defaults will be nil
        UserDefaults.standard.register(defaults: SGSimpleSettings.groupDefaultValues)
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            groupUserDefaults.register(defaults: SGSimpleSettings.groupDefaultValues)
        }
    }
    
    private func migrate() {
        let showRepostToStoryMigrationKey = "migrated_\(Keys.showRepostToStory.rawValue)"
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            if !groupUserDefaults.bool(forKey: showRepostToStoryMigrationKey) {
                self.showRepostToStoryV2 = self.showRepostToStory
                groupUserDefaults.set(true, forKey: showRepostToStoryMigrationKey)
                SGLogger.shared.log("SGSimpleSettings", "Migrated showRepostToStory. \(self.showRepostToStory) -> \(self.showRepostToStoryV2)")
            }
        } else {
            SGLogger.shared.log("SGSimpleSettings", "Unable to migrate showRepostToStory. Shared UserDefaults suite is not available for '\(APP_GROUP_IDENTIFIER)'.")
        }

        let chatListLinesMigrationKey = "migrated_\(Keys.chatListLines.rawValue)"
        if !UserDefaults.standard.bool(forKey: chatListLinesMigrationKey) {
            let legacyCompactMessagePreviewKey = "compactMessagePreview"
            if UserDefaults.standard.object(forKey: legacyCompactMessagePreviewKey) != nil {
                if UserDefaults.standard.bool(forKey: legacyCompactMessagePreviewKey) {
                    self.chatListLines = ChatListLines.one.rawValue
                }
                UserDefaults.standard.removeObject(forKey: legacyCompactMessagePreviewKey)
                SGLogger.shared.log("SGSimpleSettings", "Migrated compactMessagePreview -> chatListLines. \(self.chatListLines)")
            }
            UserDefaults.standard.set(true, forKey: chatListLinesMigrationKey)
        }
    }
    
    private func preCacheValues() {
        // let dispatchGroup = DispatchGroup()

        let tasks = [
//            { let _ = self.allChatsFolderPositionOverride },
            { let _ = self.tabBarSearchEnabled },
            { let _ = self.ghostMode },
            { let _ = self.ghostHideOnline },
            { let _ = self.ghostNoReadReceipts },
            { let _ = self.ghostNoTyping },
            { let _ = self.ghostNoStoryViews },
            { let _ = self.ghostReadOnReply },
            { let _ = self.saveDeletedMessages },
            { let _ = self.saveEditHistory },
            { let _ = self.allChatsHidden },
            { let _ = self.hideTabBar },
            { let _ = self.bottomTabStyle },
            { let _ = self.compactChatList },
            { let _ = self.chatListLines },
            { let _ = self.compactFolderNames },
            { let _ = self.disableSwipeToRecordStory },
            { let _ = self.rememberLastFolder },
            { let _ = self.quickTranslateButton },
            { let _ = self.stickerSize },
            { let _ = self.stickerTimestamp },
            { let _ = self.hideReactions },
            { let _ = self.disableGalleryCamera },
            { let _ = self.disableSendAsButton },
            { let _ = self.disableSnapDeletionEffect },
            { let _ = self.startTelescopeWithRearCam },
            { let _ = self.hideRecordingButton },
            { let _ = self.inputToolbar },
            { let _ = self.dismissedSGSuggestions },
            { let _ = self.customAppBadge }
        ]

        tasks.forEach { task in
            DispatchQueue.global(qos: .background).async(/*group: dispatchGroup*/) {
                task()
            }
        }

        // dispatchGroup.notify(queue: DispatchQueue.main) {}
    }
    
    public func synchronizeShared() {
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            groupUserDefaults.synchronize()
        }
    }
    
    public enum Keys: String, CaseIterable {
        case hidePhoneInSettings
        case showTabNames
        case startTelescopeWithRearCam
        case accountColorsSaturation
        case uploadSpeedBoost
        case downloadSpeedBoost
        case bottomTabStyle
        case rememberLastFolder
        case lastAccountFolders
        case localDNSForProxyHost
        case sendLargePhotos
        case outgoingPhotoQuality
        case storyStealthMode
        case canUseStealthMode
        // MARK: HolyGram ghost mode
        case ghostMode
        case ghostHideOnline
        case ghostNoReadReceipts
        case ghostNoTyping
        case ghostNoStoryViews
        case ghostReadOnReply
        case ghostReadExceptions
        case hideInAppSwitcher
        case hideSponsoredMessages
        case keepSelfDestructingMedia
        case streamerMode
        case hidePaidFeatureRows
        case confirmStickerSend
        case hideBlockedUsersMessages
        case hideFolderBadges
        case hideSimilarChannels
        case hiddenChats
        case lockedChats
        case highlightKeywords
        case silentChats
        case hgShowGhostButton
        case menuGhostException
        case menuHideChat
        case menuLockChat
        case menuSilentChat
        case menuCopyId
        case menuDeleteMine
        case menuBookmark
        case menuRemind
        case menuChatStats
        case menuSaveAllMedia
        case menuEditHistory
        case menuExportChat
        case menuFirstMessage
        case menuTemplates
        case menuChatNote
        case confirmVoiceSend
        case saveDeletedMessages
        case saveEditHistory
        case disableSwipeToRecordStory
        case quickTranslateButton
        case outgoingLanguageTranslation
        case hideReactions
        case showRepostToStory
        case showRepostToStoryV2
        case contextShowSelectFromUser
        case contextShowSaveToCloud
        case contextShowRestrict
        // case contextShowBan
        case contextShowHideForwardName
        case contextShowReport
        case contextShowReply
        case contextShowPin
        case contextShowSaveMedia
        case contextShowMessageReplies
        case contextShowJson
        case contextShowRepeat // MARK: HolyGram
        case disableScrollToNextChannel
        case disableScrollToNextTopic
        case disableChatSwipeOptions
        case disableDeleteChatSwipeOption
        case disableGalleryCamera
        case disableGalleryCameraPreview
        case disableSendAsButton
        case disableSnapDeletionEffect
        case stickerSize
        case stickerTimestamp
        case hideRecordingButton
        case hideTabBar
        case showDC
        case showCreationDate
        case showRegDate
        case regDateCache
        case compactChatList
        case chatListLines
        case compactFolderNames
        case allChatsTitleLengthOverride
//        case allChatsFolderPositionOverride
        case allChatsHidden
        case defaultEmojisFirst
        case messageDoubleTapActionOutgoing
        case wideChannelPosts
        case forceEmojiTab
        case forceBuiltInMic
        case secondsInMessages
        case hideChannelBottomButton
        case forceSystemSharing
        case confirmCalls
        case videoPIPSwipeDirection
        case legacyNotificationsFix
        case messageFilterKeywords
        case inputToolbar
        case pinnedMessageNotifications
        case mentionsAndRepliesNotifications
        case primaryUserId
        case status
        case dismissedSGSuggestions
        case duckyAppIconAvailable
        case transcriptionBackend
        case translationBackend
        case translatorLogsExpiration
        case customAppBadge
        case canUseNY
        case nyStyle
        case wideTabBar
        case tabBarSearchEnabled
        case hideStories
        case warnOnStoriesOpen
        case showProfileId
        case sendWithReturnKey
        case videoControlsInFooter
        case hideAccountInNotifications
    }
    
    public enum DownloadSpeedBoostValues: String, CaseIterable {
        case none
        case medium
        case maximum
    }
    
    public enum BottomTabStyleValues: String, CaseIterable {
        case telegram
        case ios
    }
    
    public enum AllChatsTitleLengthOverride: String, CaseIterable {
        case none
        case short
        case long
    }
    
    public enum AllChatsFolderPositionOverride: String, CaseIterable {
        case none
        case last
        case hidden
    }

    public enum ChatListLines: String, CaseIterable {
        case three = "3"
        case two = "2"
        case one = "1"

        public static let defaultValue: ChatListLines = .three
    }
    
    public enum MessageDoubleTapAction: String, CaseIterable {
        case `default`
        case none
        case edit
    }
    
    public enum VideoPIPSwipeDirection: String, CaseIterable {
        case up
        case down
        case none
    }

    public enum TranscriptionBackend: String, CaseIterable {
        case `default`
        case apple
    }

    public enum TranslationBackend: String, CaseIterable {
        case `default`
        case gtranslate
        case system
        // Make sure to update TranslationConfiguration
    }
        
    public enum PinnedMessageNotificationsSettings: String, CaseIterable {
        case `default`
        case silenced
        case disabled
    }
    
    public enum MentionsAndRepliesNotificationsSettings: String, CaseIterable {
        case `default`
        case silenced
        case disabled
    }

    public enum NYStyle: String, CaseIterable {
        case `default`
        case snow
        case lightning
    }
    
    public static let defaultValues: [String: Any] = [
        Keys.hidePhoneInSettings.rawValue: true,
        Keys.showTabNames.rawValue: true,
        Keys.startTelescopeWithRearCam.rawValue: false,
        Keys.accountColorsSaturation.rawValue: 100,
        Keys.uploadSpeedBoost.rawValue: false,
        Keys.downloadSpeedBoost.rawValue: DownloadSpeedBoostValues.none.rawValue,
        Keys.rememberLastFolder.rawValue: false,
        Keys.bottomTabStyle.rawValue: BottomTabStyleValues.telegram.rawValue,
        Keys.lastAccountFolders.rawValue: [:],
        Keys.localDNSForProxyHost.rawValue: false,
        Keys.sendLargePhotos.rawValue: false,
        Keys.outgoingPhotoQuality.rawValue: 70,
        Keys.storyStealthMode.rawValue: false,
        Keys.canUseStealthMode.rawValue: true,
        Keys.ghostMode.rawValue: false,
        Keys.ghostHideOnline.rawValue: true,
        Keys.ghostNoReadReceipts.rawValue: true,
        Keys.ghostNoTyping.rawValue: true,
        Keys.ghostNoStoryViews.rawValue: true,
        Keys.ghostReadOnReply.rawValue: true,
        Keys.ghostReadExceptions.rawValue: [String](),
        Keys.hideInAppSwitcher.rawValue: false,
        Keys.hideSponsoredMessages.rawValue: true,
        Keys.keepSelfDestructingMedia.rawValue: false,
        Keys.streamerMode.rawValue: false,
        Keys.hidePaidFeatureRows.rawValue: false,
        Keys.confirmStickerSend.rawValue: false,
        Keys.hideBlockedUsersMessages.rawValue: false,
        Keys.hideFolderBadges.rawValue: false,
        Keys.hideSimilarChannels.rawValue: false,
        Keys.hiddenChats.rawValue: [String](),
        Keys.lockedChats.rawValue: [String](),
        Keys.highlightKeywords.rawValue: [String](),
        Keys.silentChats.rawValue: [String](),
        Keys.hgShowGhostButton.rawValue: true,
        Keys.menuGhostException.rawValue: true,
        Keys.menuHideChat.rawValue: true,
        Keys.menuLockChat.rawValue: true,
        Keys.menuSilentChat.rawValue: true,
        Keys.menuCopyId.rawValue: true,
        Keys.menuDeleteMine.rawValue: true,
        Keys.menuBookmark.rawValue: true,
        Keys.menuRemind.rawValue: true,
        Keys.menuChatStats.rawValue: true,
        Keys.menuSaveAllMedia.rawValue: true,
        Keys.menuEditHistory.rawValue: true,
        Keys.menuExportChat.rawValue: true,
        Keys.menuFirstMessage.rawValue: true,
        Keys.menuTemplates.rawValue: true,
        Keys.menuChatNote.rawValue: true,
        Keys.confirmVoiceSend.rawValue: false,
        Keys.saveDeletedMessages.rawValue: true,
        Keys.saveEditHistory.rawValue: true,
        Keys.disableSwipeToRecordStory.rawValue: false,
        Keys.quickTranslateButton.rawValue: false,
        Keys.outgoingLanguageTranslation.rawValue: [:],
        Keys.hideReactions.rawValue: false,
        Keys.showRepostToStory.rawValue: true,
        Keys.contextShowSelectFromUser.rawValue: true,
        Keys.contextShowSaveToCloud.rawValue: true,
        Keys.contextShowRestrict.rawValue: true,
        // Keys.contextShowBan.rawValue: true,
        Keys.contextShowHideForwardName.rawValue: true,
        Keys.contextShowReport.rawValue: true,
        Keys.contextShowReply.rawValue: true,
        Keys.contextShowPin.rawValue: true,
        Keys.contextShowSaveMedia.rawValue: true,
        Keys.contextShowMessageReplies.rawValue: true,
        Keys.contextShowJson.rawValue: false,
        Keys.contextShowRepeat.rawValue: true,
        Keys.disableScrollToNextChannel.rawValue: false,
        Keys.disableScrollToNextTopic.rawValue: false,
        Keys.disableChatSwipeOptions.rawValue: false,
        Keys.disableDeleteChatSwipeOption.rawValue: false,
        Keys.disableGalleryCamera.rawValue: false,
        Keys.disableGalleryCameraPreview.rawValue: false,
        Keys.disableSendAsButton.rawValue: false,
        Keys.disableSnapDeletionEffect.rawValue: false,
        Keys.stickerSize.rawValue: 100,
        Keys.stickerTimestamp.rawValue: true,
        Keys.hideRecordingButton.rawValue: false,
        Keys.hideTabBar.rawValue: false,
        Keys.showDC.rawValue: false,
        Keys.showCreationDate.rawValue: true,
        Keys.showRegDate.rawValue: true,
        Keys.regDateCache.rawValue: [:],
        Keys.compactChatList.rawValue: false,
        Keys.chatListLines.rawValue: ChatListLines.defaultValue.rawValue,
        Keys.compactFolderNames.rawValue: false,
        Keys.allChatsTitleLengthOverride.rawValue: AllChatsTitleLengthOverride.none.rawValue,
//        Keys.allChatsFolderPositionOverride.rawValue: AllChatsFolderPositionOverride.none.rawValue
        Keys.allChatsHidden.rawValue: false,
        Keys.defaultEmojisFirst.rawValue: false,
        Keys.messageDoubleTapActionOutgoing.rawValue: MessageDoubleTapAction.default.rawValue,
        Keys.wideChannelPosts.rawValue: false,
        Keys.forceEmojiTab.rawValue: false,
        Keys.hideChannelBottomButton.rawValue: false,
        Keys.secondsInMessages.rawValue: false,
        Keys.forceSystemSharing.rawValue: false,
        Keys.confirmCalls.rawValue: true,
        Keys.videoPIPSwipeDirection.rawValue: VideoPIPSwipeDirection.up.rawValue,
        Keys.messageFilterKeywords.rawValue: [],
        Keys.inputToolbar.rawValue: false,
        Keys.primaryUserId.rawValue: "",
        Keys.dismissedSGSuggestions.rawValue: [],
        Keys.duckyAppIconAvailable.rawValue: true,
        Keys.transcriptionBackend.rawValue: TranscriptionBackend.default.rawValue,
        Keys.translationBackend.rawValue: TranslationBackend.default.rawValue,
        Keys.translatorLogsExpiration.rawValue: 0.0,
        Keys.customAppBadge.rawValue: "",
        Keys.canUseNY.rawValue: false,
        Keys.nyStyle.rawValue: NYStyle.default.rawValue,
        Keys.wideTabBar.rawValue: false,
        Keys.tabBarSearchEnabled.rawValue: true,
        Keys.hideStories.rawValue: false,
        Keys.warnOnStoriesOpen.rawValue: false,
        Keys.showProfileId.rawValue: true,
        Keys.sendWithReturnKey.rawValue: false,
        Keys.videoControlsInFooter.rawValue: false,
    ]
    
    public static let groupDefaultValues: [String: Any] = [
        Keys.legacyNotificationsFix.rawValue: false,
        Keys.pinnedMessageNotifications.rawValue: PinnedMessageNotificationsSettings.default.rawValue,
        Keys.mentionsAndRepliesNotifications.rawValue: MentionsAndRepliesNotificationsSettings.default.rawValue,
        Keys.status.rawValue: 2, // MARK: HolyGram: Pro always on
        Keys.showRepostToStoryV2.rawValue: true,
        Keys.hideAccountInNotifications.rawValue: false,
    ]
    
    @UserDefault(key: Keys.hidePhoneInSettings.rawValue)
    public var hidePhoneInSettings: Bool
    
    @UserDefault(key: Keys.showTabNames.rawValue)
    public var showTabNames: Bool
    
    @UserDefault(key: Keys.startTelescopeWithRearCam.rawValue)
    public var startTelescopeWithRearCam: Bool
    
    @UserDefault(key: Keys.accountColorsSaturation.rawValue)
    public var accountColorsSaturation: Int32
    
    @UserDefault(key: Keys.uploadSpeedBoost.rawValue)
    public var uploadSpeedBoost: Bool
    
    @UserDefault(key: Keys.downloadSpeedBoost.rawValue)
    public var downloadSpeedBoost: String
    
    @UserDefault(key: Keys.rememberLastFolder.rawValue)
    public var rememberLastFolder: Bool
    
    // Disabled while Telegram is migrating to Glass
    // @UserDefault(key: Keys.bottomTabStyle.rawValue)
    public var bottomTabStyle: String {
        set {}
        get {
            return BottomTabStyleValues.ios.rawValue
        }
    }
    
    public var lastAccountFolders = UserDefaultsBackedDictionary<String, Int32>(userDefaultsKey: Keys.lastAccountFolders.rawValue, threadSafe: false)
    
    @UserDefault(key: Keys.localDNSForProxyHost.rawValue)
    public var localDNSForProxyHost: Bool
    
    @UserDefault(key: Keys.sendLargePhotos.rawValue)
    public var sendLargePhotos: Bool
    
    @UserDefault(key: Keys.outgoingPhotoQuality.rawValue)
    public var outgoingPhotoQuality: Int32

    @UserDefault(key: Keys.hideStories.rawValue)
    public var hideStories: Bool

    @UserDefault(key: Keys.warnOnStoriesOpen.rawValue)
    public var warnOnStoriesOpen: Bool
    
    @UserDefault(key: Keys.storyStealthMode.rawValue)
    public var storyStealthMode: Bool
    
    @UserDefault(key: Keys.canUseStealthMode.rawValue)
    public var canUseStealthMode: Bool    

    // MARK: HolyGram ghost mode
    @UserDefault(key: Keys.ghostMode.rawValue)
    public var ghostMode: Bool

    @UserDefault(key: Keys.ghostHideOnline.rawValue)
    public var ghostHideOnline: Bool

    @UserDefault(key: Keys.ghostNoReadReceipts.rawValue)
    public var ghostNoReadReceipts: Bool

    @UserDefault(key: Keys.ghostNoTyping.rawValue)
    public var ghostNoTyping: Bool

    @UserDefault(key: Keys.ghostNoStoryViews.rawValue)
    public var ghostNoStoryViews: Bool

    /// Send the read receipt for a chat when replying in it, even in ghost mode.
    @UserDefault(key: Keys.ghostReadOnReply.rawValue)
    public var ghostReadOnReply: Bool

    /// Chats (peer ids) where read receipts are sent even in ghost mode.
    @UserDefault(key: Keys.ghostReadExceptions.rawValue)
    public var ghostReadExceptions: [String]

    // MARK: HolyGram privacy
    /// Blur the app in the app switcher.
    @UserDefault(key: Keys.hideInAppSwitcher.rawValue)
    public var hideInAppSwitcher: Bool

    /// Don't load sponsored messages in channels.
    @UserDefault(key: Keys.hideSponsoredMessages.rawValue)
    public var hideSponsoredMessages: Bool

    /// Self-destructing photos and videos in cloud chats stay viewable after their timer.
    @UserDefault(key: Keys.keepSelfDestructingMedia.rawValue)
    public var keepSelfDestructingMedia: Bool

    /// Hide the app from screenshots, screen recordings and screen sharing.
    @UserDefault(key: Keys.streamerMode.rawValue)
    public var streamerMode: Bool

    /// Hide the Premium, Stars, TON, Business and Gifts rows in Settings.
    @UserDefault(key: Keys.hidePaidFeatureRows.rawValue)
    public var hidePaidFeatureRows: Bool

    // MARK: HolyGram: ask before sending
    @UserDefault(key: Keys.confirmStickerSend.rawValue)
    public var confirmStickerSend: Bool

    /// Hide messages of blocked users in groups.
    @UserDefault(key: Keys.hideBlockedUsersMessages.rawValue)
    public var hideBlockedUsersMessages: Bool

    /// Hide unread counters on chat folder tabs.
    @UserDefault(key: Keys.hideFolderBadges.rawValue)
    public var hideFolderBadges: Bool

    /// Hide the "Similar channels" block and profile tab.
    @UserDefault(key: Keys.hideSimilarChannels.rawValue)
    public var hideSimilarChannels: Bool

    /// Chats (peer ids) left out of the chat list; listed in HolyGram settings behind Face ID.
    @UserDefault(key: Keys.hiddenChats.rawValue)
    public var hiddenChats: [String]

    /// Chats (peer ids) that need Face ID to open.
    @UserDefault(key: Keys.lockedChats.rawValue)
    public var lockedChats: [String]

    /// Words highlighted in message text, case-insensitive.
    @UserDefault(key: Keys.highlightKeywords.rawValue)
    public var highlightKeywords: [String]

    /// Chats (peer ids) where messages are always sent without sound.
    @UserDefault(key: Keys.silentChats.rawValue)
    public var silentChats: [String]

    // MARK: HolyGram: which HolyGram items appear in menus
    /// Show the ghost mode eye above the chat list.
    @UserDefault(key: Keys.hgShowGhostButton.rawValue)
    public var hgShowGhostButton: Bool

    /// Chat menu: send read receipts here.
    @UserDefault(key: Keys.menuGhostException.rawValue)
    public var menuGhostException: Bool

    /// Chat menu: hide chat.
    @UserDefault(key: Keys.menuHideChat.rawValue)
    public var menuHideChat: Bool

    /// Chat menu: lock with Face ID.
    @UserDefault(key: Keys.menuLockChat.rawValue)
    public var menuLockChat: Bool

    /// Chat menu: always send silently.
    @UserDefault(key: Keys.menuSilentChat.rawValue)
    public var menuSilentChat: Bool

    /// Chat menu: copy ID and link.
    @UserDefault(key: Keys.menuCopyId.rawValue)
    public var menuCopyId: Bool

    /// Chat menu: delete all my messages.
    @UserDefault(key: Keys.menuDeleteMine.rawValue)
    public var menuDeleteMine: Bool

    /// Message menu: bookmark.
    @UserDefault(key: Keys.menuBookmark.rawValue)
    public var menuBookmark: Bool

    /// Message menu: remind me.
    @UserDefault(key: Keys.menuRemind.rawValue)
    public var menuRemind: Bool

    /// Message menu: chat statistics.
    @UserDefault(key: Keys.menuChatStats.rawValue)
    public var menuChatStats: Bool

    /// Message menu: save all chat media.
    @UserDefault(key: Keys.menuSaveAllMedia.rawValue)
    public var menuSaveAllMedia: Bool

    /// Message menu: edit history.
    @UserDefault(key: Keys.menuEditHistory.rawValue)
    public var menuEditHistory: Bool

    /// Message menu: export the chat to a text file.
    @UserDefault(key: Keys.menuExportChat.rawValue)
    public var menuExportChat: Bool

    /// Message menu: jump to the first message.
    @UserDefault(key: Keys.menuFirstMessage.rawValue)
    public var menuFirstMessage: Bool

    /// Message menu: message templates.
    @UserDefault(key: Keys.menuTemplates.rawValue)
    public var menuTemplates: Bool

    /// Chat menu: a private note about the chat.
    @UserDefault(key: Keys.menuChatNote.rawValue)
    public var menuChatNote: Bool

    @UserDefault(key: Keys.confirmVoiceSend.rawValue)
    public var confirmVoiceSend: Bool

    // MARK: HolyGram message history
    @UserDefault(key: Keys.saveDeletedMessages.rawValue)
    public var saveDeletedMessages: Bool

    @UserDefault(key: Keys.saveEditHistory.rawValue)
    public var saveEditHistory: Bool
    
    @UserDefault(key: Keys.disableSwipeToRecordStory.rawValue)
    public var disableSwipeToRecordStory: Bool   
    
    @UserDefault(key: Keys.quickTranslateButton.rawValue)
    public var quickTranslateButton: Bool
    
    public var outgoingLanguageTranslation = UserDefaultsBackedDictionary<String, String>(userDefaultsKey: Keys.outgoingLanguageTranslation.rawValue, threadSafe: false)
    
    @UserDefault(key: Keys.hideReactions.rawValue)
    public var hideReactions: Bool

    // @available(*, deprecated, message: "Use showRepostToStoryV2 instead")
    @UserDefault(key: Keys.showRepostToStory.rawValue)
    public var showRepostToStory: Bool

    @UserDefault(key: Keys.showRepostToStoryV2.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var showRepostToStoryV2: Bool

    @UserDefault(key: Keys.contextShowRestrict.rawValue)
    public var contextShowRestrict: Bool

    /*@UserDefault(key: Keys.contextShowBan.rawValue)
    public var contextShowBan: Bool*/

    @UserDefault(key: Keys.contextShowSelectFromUser.rawValue)
    public var contextShowSelectFromUser: Bool

    @UserDefault(key: Keys.contextShowSaveToCloud.rawValue)
    public var contextShowSaveToCloud: Bool

    @UserDefault(key: Keys.contextShowHideForwardName.rawValue)
    public var contextShowHideForwardName: Bool

    @UserDefault(key: Keys.contextShowReport.rawValue)
    public var contextShowReport: Bool

    @UserDefault(key: Keys.contextShowReply.rawValue)
    public var contextShowReply: Bool

    @UserDefault(key: Keys.contextShowPin.rawValue)
    public var contextShowPin: Bool

    @UserDefault(key: Keys.contextShowSaveMedia.rawValue)
    public var contextShowSaveMedia: Bool

    @UserDefault(key: Keys.contextShowMessageReplies.rawValue)
    public var contextShowMessageReplies: Bool
    
    @UserDefault(key: Keys.contextShowJson.rawValue)
    public var contextShowJson: Bool

    // MARK: HolyGram: "+1" repeats a message in the same chat
    @UserDefault(key: Keys.contextShowRepeat.rawValue)
    public var contextShowRepeat: Bool
    
    @UserDefault(key: Keys.disableScrollToNextChannel.rawValue)
    public var disableScrollToNextChannel: Bool

    @UserDefault(key: Keys.disableScrollToNextTopic.rawValue)
    public var disableScrollToNextTopic: Bool

    @UserDefault(key: Keys.disableChatSwipeOptions.rawValue)
    public var disableChatSwipeOptions: Bool

    @UserDefault(key: Keys.disableDeleteChatSwipeOption.rawValue)
    public var disableDeleteChatSwipeOption: Bool

    @UserDefault(key: Keys.disableGalleryCamera.rawValue)
    public var disableGalleryCamera: Bool

    @UserDefault(key: Keys.disableGalleryCameraPreview.rawValue)
    public var disableGalleryCameraPreview: Bool

    @UserDefault(key: Keys.disableSendAsButton.rawValue)
    public var disableSendAsButton: Bool

    @UserDefault(key: Keys.disableSnapDeletionEffect.rawValue)
    public var disableSnapDeletionEffect: Bool
    
    @UserDefault(key: Keys.stickerSize.rawValue)
    public var stickerSize: Int32
    
    @UserDefault(key: Keys.stickerTimestamp.rawValue)
    public var stickerTimestamp: Bool    

    @UserDefault(key: Keys.hideRecordingButton.rawValue)
    public var hideRecordingButton: Bool
    
    @UserDefault(key: Keys.hideTabBar.rawValue)
    public var hideTabBar: Bool

    @UserDefault(key: Keys.showProfileId.rawValue)
    public var showProfileId: Bool
    
    @UserDefault(key: Keys.showDC.rawValue)
    public var showDC: Bool
    
    @UserDefault(key: Keys.showCreationDate.rawValue)
    public var showCreationDate: Bool

    @UserDefault(key: Keys.showRegDate.rawValue)
    public var showRegDate: Bool

    public var regDateCache = UserDefaultsBackedDictionary<String, Data>(userDefaultsKey: Keys.regDateCache.rawValue, threadSafe: false)
    
    @UserDefault(key: Keys.compactChatList.rawValue)
    public var compactChatList: Bool

    @UserDefault(key: Keys.chatListLines.rawValue)
    public var chatListLines: String

    @UserDefault(key: Keys.compactFolderNames.rawValue)
    public var compactFolderNames: Bool
    
    @UserDefault(key: Keys.allChatsTitleLengthOverride.rawValue)
    public var allChatsTitleLengthOverride: String
//    
//    @UserDefault(key: Keys.allChatsFolderPositionOverride.rawValue)
//    public var allChatsFolderPositionOverride: String
    @UserDefault(key: Keys.allChatsHidden.rawValue)
    public var allChatsHidden: Bool

    @UserDefault(key: Keys.defaultEmojisFirst.rawValue)
    public var defaultEmojisFirst: Bool
    
    @UserDefault(key: Keys.messageDoubleTapActionOutgoing.rawValue)
    public var messageDoubleTapActionOutgoing: String
    
    @UserDefault(key: Keys.wideChannelPosts.rawValue)
    public var wideChannelPosts: Bool

    @UserDefault(key: Keys.forceEmojiTab.rawValue)
    public var forceEmojiTab: Bool
    
    @UserDefault(key: Keys.forceBuiltInMic.rawValue)
    public var forceBuiltInMic: Bool
    
    @UserDefault(key: Keys.secondsInMessages.rawValue)
    public var secondsInMessages: Bool
    
    @UserDefault(key: Keys.hideChannelBottomButton.rawValue)
    public var hideChannelBottomButton: Bool

    @UserDefault(key: Keys.forceSystemSharing.rawValue)
    public var forceSystemSharing: Bool

    @UserDefault(key: Keys.confirmCalls.rawValue)
    public var confirmCalls: Bool
    
    @UserDefault(key: Keys.videoPIPSwipeDirection.rawValue)
    public var videoPIPSwipeDirection: String

    @UserDefault(key: Keys.legacyNotificationsFix.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var legacyNotificationsFix: Bool
    
    @UserDefault(key: Keys.status.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var status: Int64

    public var ephemeralStatus: Int64 = 2 // MARK: HolyGram: Pro always on
    
    @UserDefault(key: Keys.messageFilterKeywords.rawValue)
    public var messageFilterKeywords: [String]
    
    @UserDefault(key: Keys.inputToolbar.rawValue)
    public var inputToolbar: Bool

    @UserDefault(key: Keys.sendWithReturnKey.rawValue)
    public var sendWithReturnKey: Bool
    
    @UserDefault(key: Keys.pinnedMessageNotifications.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var pinnedMessageNotifications: String
    
    @UserDefault(key: Keys.mentionsAndRepliesNotifications.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var mentionsAndRepliesNotifications: String
    
    @UserDefault(key: Keys.primaryUserId.rawValue)
    public var primaryUserId: String

    @UserDefault(key: Keys.dismissedSGSuggestions.rawValue)
    public var dismissedSGSuggestions: [String]

    @UserDefault(key: Keys.duckyAppIconAvailable.rawValue)
    public var duckyAppIconAvailable: Bool

    @UserDefault(key: Keys.transcriptionBackend.rawValue)
    public var transcriptionBackend: String

    @UserDefault(key: Keys.translationBackend.rawValue)
    public var translationBackend: String

    @UserDefault(key: Keys.translatorLogsExpiration.rawValue)
    private var translatorLogsExpiration: Double

    public var translatorLogsEnabled: Bool {
        if self.translatorLogsExpiration > Date().timeIntervalSince1970 {
            return true
        }
        if self.translatorLogsExpiration != 0.0 {
            self.translatorLogsExpiration = 0.0
        }
        return false
    }

    public func setTranslatorLogsEnabled(_ enabled: Bool) {
        self.translatorLogsExpiration = enabled ? Date().addingTimeInterval(24.0 * 60.0 * 60.0).timeIntervalSince1970 : 0.0
    }

    @UserDefault(key: Keys.customAppBadge.rawValue)
    public var customAppBadge: String

    @UserDefault(key: Keys.canUseNY.rawValue)
    public var canUseNY: Bool

    @UserDefault(key: Keys.nyStyle.rawValue)
    public var nyStyle: String

    @UserDefault(key: Keys.wideTabBar.rawValue)
    public var wideTabBar: Bool
    
    @UserDefault(key: Keys.tabBarSearchEnabled.rawValue)
    public var tabBarSearchEnabled: Bool

    @UserDefault(key: Keys.videoControlsInFooter.rawValue)
    public var videoControlsInFooter: Bool

    @UserDefault(key: Keys.hideAccountInNotifications.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var hideAccountInNotifications: Bool
}

extension SGSimpleSettings {
    public var isStealthModeEnabled: Bool {
        return storyStealthMode && canUseStealthMode
    }

    // MARK: HolyGram Pro: the effective values of paid features
    /// Pro features work only with an active HolyGram Pro subscription.
    public var hgPro: Bool { HolyGramPro.shared.isActive }
    /// The admin bot can switch these off for everyone (/disable), e.g. on a request from Telegram.
    public var hgGhostAvailable: Bool { !HolyGramPro.shared.isRemotelyDisabled("ghost") }
    public var hgSelfDestructAvailable: Bool { !HolyGramPro.shared.isRemotelyDisabled("selfdestruct") }
    public var hgDeletedAvailable: Bool { !HolyGramPro.shared.isRemotelyDisabled("deleted") }
    public var hgEditsAvailable: Bool { !HolyGramPro.shared.isRemotelyDisabled("edits") }

    // MARK: HolyGram ghost mode
    private var ghostActive: Bool { ghostMode && hgGhostAvailable && hgPro }
    /// Never report "online"; the account always looks offline.
    public var ghostBlocksOnline: Bool { ghostActive && ghostHideOnline }
    /// Messages are marked read locally only; the sender keeps seeing them as unread.
    public var ghostBlocksReadReceipts: Bool { ghostActive && ghostNoReadReceipts }
    /// Same, except in chats the user excluded from ghost mode.
    public func ghostBlocksReadReceiptsInChat(_ peerIdValue: Int64) -> Bool {
        return ghostBlocksReadReceipts && !ghostReadExceptions.contains(String(peerIdValue))
    }
    public func isGhostReadException(_ peerIdValue: Int64) -> Bool {
        return ghostReadExceptions.contains(String(peerIdValue))
    }
    public func setGhostReadException(_ peerIdValue: Int64, _ enabled: Bool) {
        var list = ghostReadExceptions.filter { $0 != String(peerIdValue) }
        if enabled {
            list.append(String(peerIdValue))
        }
        ghostReadExceptions = list
    }
    /// "typing…", "recording voice…" and similar activities are not sent.
    public var ghostBlocksTyping: Bool { ghostActive && ghostNoTyping }
    /// Stories are viewed without the author seeing it.
    public var ghostBlocksStoryViews: Bool { ghostActive && ghostNoStoryViews }

    public var hgSaveDeletedMessages: Bool { saveDeletedMessages && hgDeletedAvailable && hgPro }
    public var hgSaveEditHistory: Bool { saveEditHistory && hgEditsAvailable && hgPro }
    public var hgKeepSelfDestructingMedia: Bool { keepSelfDestructingMedia && hgSelfDestructAvailable && hgPro }
    public var hgHideSponsoredMessages: Bool { hideSponsoredMessages && hgPro }
    public var hgStreamerMode: Bool { streamerMode && hgPro }
    public var hgHideInAppSwitcher: Bool { hideInAppSwitcher && hgPro }
    public var hgShowRepeat: Bool { contextShowRepeat && hgPro }
    public var hgConfirmStickerSend: Bool { confirmStickerSend && hgPro }
    public var hgConfirmVoiceSend: Bool { confirmVoiceSend && hgPro }
    public var hgHideBlockedUsersMessages: Bool { hideBlockedUsersMessages && hgPro }
    
    public static func makeOutgoingLanguageTranslationKey(accountId: Int64, peerId: Int64) -> String {
        return "\(accountId):\(peerId)"
    }
}

extension SGSimpleSettings {
    public var translationBackendEnum: SGSimpleSettings.TranslationBackend {
        return TranslationBackend(rawValue: translationBackend) ?? .default
    }
    
    public var transcriptionBackendEnum: SGSimpleSettings.TranscriptionBackend {
        return TranscriptionBackend(rawValue: transcriptionBackend) ?? .default
    }
}

extension SGSimpleSettings {
    public var isNYEnabled: Bool {
        return canUseNY && NYStyle(rawValue: nyStyle) != .default
    }
}

public func getSGDownloadPartSize(_ default: Int64, fileSize: Int64?) -> Int64 {
    let currentDownloadSetting = SGSimpleSettings.shared.downloadSpeedBoost
    // Increasing chunk size for small files make it worse in terms of overall download performance
    let smallFileSizeThreshold = 1 * 1024 * 1024 // 1 MB
    switch (currentDownloadSetting) {
        case SGSimpleSettings.DownloadSpeedBoostValues.medium.rawValue:
            if let fileSize, fileSize <= smallFileSizeThreshold {
                return `default`
            }
            return 512 * 1024
        case SGSimpleSettings.DownloadSpeedBoostValues.maximum.rawValue:
            if let fileSize, fileSize <= smallFileSizeThreshold {
                return `default`
            }
            return 1024 * 1024
        default:
            return `default`
    }
}

public func getSGMaxPendingParts(_ default: Int) -> Int {
    let currentDownloadSetting = SGSimpleSettings.shared.downloadSpeedBoost
    switch (currentDownloadSetting) {
        case SGSimpleSettings.DownloadSpeedBoostValues.medium.rawValue:
            return 8
        case SGSimpleSettings.DownloadSpeedBoostValues.maximum.rawValue:
            return 12
        default:
            return `default`
    }
}

public func sgUseShortAllChatsTitle(_ default: Bool) -> Bool {
    let currentOverride = SGSimpleSettings.shared.allChatsTitleLengthOverride
    switch (currentOverride) {
        case SGSimpleSettings.AllChatsTitleLengthOverride.short.rawValue:
            return true
        case SGSimpleSettings.AllChatsTitleLengthOverride.long.rawValue:
            return false
        default:
            return `default`
    }
}
