// Generates the Ed25519 key pair for signed Pro statuses.
// The private key goes to the server (wrangler secret put SIGNING_KEY);
// the public key goes into the app (HolyGramPro.swift, holyGramProPublicKey).
const { privateKey, publicKey } = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
const pkcs8 = Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64");
const raw = Buffer.from(await crypto.subtle.exportKey("raw", publicKey)).toString("base64");
console.log("SIGNING_KEY (server secret, keep private):\n" + pkcs8 + "\n");
console.log("Public key (put into the app):\n" + raw);
