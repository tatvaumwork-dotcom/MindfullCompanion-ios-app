import CommonCrypto
import Foundation

/// Reads the astrology rules files, which ship encrypted (see Scripts/encrypt-astro-data.sh).
/// Each resource is a 16-byte IV followed by AES-256-CBC ciphertext of the JSON.
///
/// This keeps the files unreadable to anyone who simply unzips the app. The key is inside the app,
/// so it does not stop someone determined enough to disassemble it.
enum AstroData {
    /// Decrypted contents of `name`.bin (e.g. "house_behaviour"), or nil if missing or unreadable.
    static func data(_ name: String, bundle: Bundle = .main) -> Data? {
        guard let url = bundle.url(forResource: name, withExtension: "bin"),
              let blob = try? Data(contentsOf: url), blob.count > kCCBlockSizeAES128 else { return nil }
        let key = zip(AstroDataKey.masked, AstroDataKey.mask).map { $0 ^ $1 }
        let iv = Data(blob.prefix(kCCBlockSizeAES128)), cipher = Data(blob.dropFirst(kCCBlockSizeAES128))
        var out = Data(count: cipher.count + kCCBlockSizeAES128)
        var moved = 0
        let status = out.withUnsafeMutableBytes { o in
            cipher.withUnsafeBytes { c in
                iv.withUnsafeBytes { v in
                    key.withUnsafeBytes { k in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                k.baseAddress, k.count, v.baseAddress, c.baseAddress, c.count, o.baseAddress, o.count, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return out.prefix(moved)
    }
}
