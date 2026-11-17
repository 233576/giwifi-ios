import Foundation
import CommonCrypto
import CryptoKit

/// GiWiFi App Portal 使用的两套编码：MD5 签名、AES-128-ECB + PKCS7，以及 Java
/// `URLEncoder.encode(value, "UTF-8")` 的等价实现。
///
/// 协议来自 APK 逆向结论（见 README「协议来源」）：
/// - 签名 = md5(按 key 字典序拼的 `k=v&k=v` + signSecret)，值不编码
/// - 载荷 = AES-128-ECB/PKCS7(base64) → 再做一次 Java form 编码
enum Crypto {

    // MARK: - MD5

    static func md5Hex(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - AES-128-ECB

    /// AES-128-ECB + PKCS7，返回 base64；失败返回 nil。
    static func aes128ECBEncryptBase64(plaintext: String, key: String) -> String? {
        let keyData = Data(key.utf8)
        guard keyData.count == kCCKeySizeAES128 else { return nil }
        let inputData = Data(plaintext.utf8)
        guard !inputData.isEmpty else { return nil }

        let bufferSize = inputData.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var encryptedLength = 0

        let status = buffer.withUnsafeMutableBytes { outBytes -> CCCryptorStatus in
            guard let outBase = outBytes.baseAddress else { return CCCryptorStatus(kCCMemoryFailure) }
            return inputData.withUnsafeBytes { inBytes -> CCCryptorStatus in
                guard let inBase = inBytes.baseAddress else { return CCCryptorStatus(kCCMemoryFailure) }
                return keyData.withUnsafeBytes { keyBytes -> CCCryptorStatus in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, keyData.count,
                        nil,
                        inBase, inputData.count,
                        outBase, bufferSize,
                        &encryptedLength
                    )
                }
            }
        }

        guard status == CCCryptorStatus(kCCSuccess) else { return nil }
        return buffer.prefix(encryptedLength).base64EncodedString()
    }

    /// AES-128-ECB 解密，用于解析响应里的 `data`（服务端有时回密文）。
    static func aes128ECBDecryptBase64(_ base64: String, key: String) -> String? {
        guard let encrypted = Data(base64Encoded: base64) else { return nil }
        let keyData = Data(key.utf8)
        guard keyData.count == kCCKeySizeAES128, encrypted.count % kCCBlockSizeAES128 == 0 else { return nil }

        let bufferSize = encrypted.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var plainLength = 0

        let status = buffer.withUnsafeMutableBytes { outBytes -> CCCryptorStatus in
            guard let outBase = outBytes.baseAddress else { return CCCryptorStatus(kCCMemoryFailure) }
            return encrypted.withUnsafeBytes { inBytes -> CCCryptorStatus in
                guard let inBase = inBytes.baseAddress else { return CCCryptorStatus(kCCMemoryFailure) }
                return keyData.withUnsafeBytes { keyBytes -> CCCryptorStatus in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, keyData.count,
                        nil,
                        inBase, encrypted.count,
                        outBase, bufferSize,
                        &plainLength
                    )
                }
            }
        }

        guard status == CCCryptorStatus(kCCSuccess) else { return nil }
        return String(data: buffer.prefix(plainLength), encoding: .utf8)
    }

    // MARK: - AES-128-CBC + ZeroPadding（Portal 网页登录用）

    /// 复刻官方 Portal 页面的 `cryptoEncode()`：
    /// ```js
    /// CryptoJS.AES.encrypt(data, Utf8.parse("1234567887654321"), {
    ///     iv: Utf8.parse(iv), mode: CBC, padding: ZeroPadding })
    /// ```
    /// 注意是 **ZeroPadding**（补 0x00），不是 PKCS7；正好对齐时不再补整块。
    static func aes128CBCZeroPadBase64(plaintext: String, key: String, iv: String) -> String? {
        let keyData = Data(key.utf8)
        let ivData = Data(iv.utf8)
        guard keyData.count == kCCKeySizeAES128, ivData.count == kCCBlockSizeAES128 else { return nil }

        var inputData = Data(plaintext.utf8)
        let remainder = inputData.count % kCCBlockSizeAES128
        if remainder != 0 {
            inputData.append(Data(repeating: 0, count: kCCBlockSizeAES128 - remainder))
        }

        let bufferSize = inputData.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var encryptedLength = 0

        let status = buffer.withUnsafeMutableBytes { outBytes -> CCCryptorStatus in
            guard let outBase = outBytes.baseAddress else { return CCCryptorStatus(kCCMemoryFailure) }
            return inputData.withUnsafeBytes { inBytes -> CCCryptorStatus in
                guard let inBase = inBytes.baseAddress else { return CCCryptorStatus(kCCMemoryFailure) }
                return keyData.withUnsafeBytes { keyBytes -> CCCryptorStatus in
                    ivData.withUnsafeBytes { ivBytes -> CCCryptorStatus in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            0,                       // 无 ECB、无 PKCS7 → 纯 CBC
                            keyBytes.baseAddress, keyData.count,
                            ivBytes.baseAddress,
                            inBase, inputData.count,
                            outBase, bufferSize,
                            &encryptedLength
                        )
                    }
                }
            }
        }

        guard status == CCCryptorStatus(kCCSuccess) else { return nil }
        return buffer.prefix(encryptedLength).base64EncodedString()
    }

    /// jQuery `$.serialize()` 的等价实现：`k=v&k=v`，值和键都按 `application/x-www-form-urlencoded` 编码
    /// （空格转 `+`，其余非安全字符 `%XX` 大写）。
    static func formSerialize(_ pairs: [(String, String)]) -> String {
        pairs
            .filter { !$0.0.isEmpty }
            .map { encodeComponent($0.0) + "=" + encodeComponent($0.1) }
            .joined(separator: "&")
    }

    private static func encodeComponent(_ value: String) -> String {
        var output = String()
        output.reserveCapacity(value.count * 3)
        for byte in value.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x5F, 0x2E, 0x2A:
                output.append(Character(UnicodeScalar(byte)))
            case 0x20:
                output.append("+")   // jQuery serialize 把空格写成 +
            default:
                output.append(String(format: "%%%02X", byte))
            }
        }
        return output
    }

    // MARK: - Java form 编码

    /// 等价于 `java.net.URLEncoder.encode(value, "UTF-8")`：
    /// 保留 `[0-9A-Za-z]` 与 `-_.*`，空格转 `+`，其余按 UTF-8 字节输出 `%XX` 大写。
    static func javaFormURLEncode(_ value: String) -> String {
        var output = String()
        output.reserveCapacity(value.count * 3)
        for byte in value.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x5F, 0x2E, 0x2A:
                output.append(Character(UnicodeScalar(byte)))
            case 0x20:
                output.append("+")
            default:
                output.append(String(format: "%%%02X", byte))
            }
        }
        return output
    }
}
