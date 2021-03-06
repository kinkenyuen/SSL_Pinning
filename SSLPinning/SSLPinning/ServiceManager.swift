//
//  ServiceManager.swift
//  SSLPinning
//
//  Created by jianqin_ruan on 2021/8/18.
//

import Foundation
import Security
import CommonCrypto

class ServiceManager: NSObject, URLSessionDelegate {
    
    static let publicKeyHash = "fO01cKyxWgDxqMQ4Q3EERIecCyqmlOQheFVlJkTvnNk="
        
    let rsa2048Asn1Header:[UInt8] = [
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
        0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
    ]
    
    private func sha256(data : Data) -> String {
        var keyWithHeader = Data(rsa2048Asn1Header)
        keyWithHeader.append(data)
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        
        keyWithHeader.withUnsafeBytes {
            _ = CC_SHA256($0, CC_LONG(keyWithHeader.count), &hash)
        }
    
        return Data(hash).base64EncodedString()
    }
    
    private var isCertificatePinning: Bool = false
    
    func callAPI(withURL url: URL, isCertificatePinning: Bool, completion: @escaping (String) -> Void) {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        self.isCertificatePinning = isCertificatePinning
        var responseMessage = ""
        let task = session.dataTask(with: url) { (data, response, error) in
            if error != nil {
                print("error: \(error!.localizedDescription): \(error!)")
                responseMessage = "Pinning failed"
            } else if data != nil {
                let str = String(decoding: data!, as: UTF8.self)
                print("Received data:\n\(str)")
                if isCertificatePinning {
                    responseMessage = "Certificate pinning is successfully completed"
                }else {
                    responseMessage = "Public key pinning is successfully completed"
                }
            }
            
            DispatchQueue.main.async {
                completion(responseMessage)
            }
            
        }
        task.resume()
    }
    
    // URLSession??????
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil);
            return
        }
        
        if self.isCertificatePinning {
            // ??????Pinning
            
            // ?????????????????????
            let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0)
            
            // SSL Policies for domain name check
            // SSL ???????????? ?????????????????????????????????
            let policy = NSMutableArray()
            policy.add(SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString))
            
            // evaluate server certifiacte
            // ?????????????????????(??????????????????????????????????)
            let isServerTrusted = SecTrustEvaluateWithError(serverTrust, nil)
            
            // Local and Remote certificate Data
            // ????????????????????????
            let remoteCertificateData:NSData =  SecCertificateCopyData(certificate!)
            // let LocalCertificate = Bundle.main.path(forResource: "github.com", ofType: "cer")
            let pathToCertificate = Bundle.main.path(forResource: "www.apple.com", ofType: "cer")
            // ????????????????????????????????????
            let localCertificateData:NSData = NSData(contentsOfFile: pathToCertificate!)!
            
            // Compare certificates
            // ????????????
            if(isServerTrusted && remoteCertificateData.isEqual(to: localCertificateData as Data)){
                let credential:URLCredential =  URLCredential(trust:serverTrust)
                print("Certificate pinning is successfully completed")
                completionHandler(.useCredential,credential)
            }
            else{
                completionHandler(.cancelAuthenticationChallenge,nil)
            }
        } else {
            // ??????Pinning
            if let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0) {
                // ?????????????????????
                let serverPublicKey = SecCertificateCopyKey(serverCertificate)
                // ???????????????data??????
                let serverPublicKeyData = SecKeyCopyExternalRepresentation(serverPublicKey!, nil )!
                let data:Data = serverPublicKeyData as Data
                // ??????????????????hash
                let serverHashKey = sha256(data: data)
                // ?????????????????????hash
                let publickKeyLocal = type(of: self).publicKeyHash
                // hash??????
                if (serverHashKey == publickKeyLocal) {
                    // ?????????????????????????????????????????????
                    print("Public key pinning is successfully completed")
                    completionHandler(.useCredential, URLCredential(trust:serverTrust))
                    return
                } else {
                    print("Public key pinning failed")
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
                }
            }
        }
    }
}

