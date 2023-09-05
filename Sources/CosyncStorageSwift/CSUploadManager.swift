//
//  CSUploadManager.swift
//
//  Licensed to the Apache Software Foundation (ASF) under one
//  or more contributor license agreements.  See the NOTICE file
//  distributed with this work for additional information
//  regarding copyright ownership.  The ASF licenses this file
//  to you under the Apache License, Version 2.0 (the
//  "License"); you may not use this file except in compliance
//  with the License.  You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the License is distributed on an
//  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
//  KIND, either express or implied.  See the License for the
//  specific language governing permissions and limitations
//  under the License.
//
//  Created by Tola Voeung on 3/19/23.
//  Copyright © 2020 cosync. All rights reserved.
//

import Foundation
import PhotosUI
import Collections
import Logging
import RealmSwift

var csLogger = Logger(label: "CSUploadManager")

@available(macOS 10.15, *)
extension URLSession {
    private static var cosyncUploadMap = [String:CosyncAssetUpload]()
    
    var csActiveUpload: CosyncAssetUpload {
        get {
            let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
            return URLSession.cosyncUploadMap[tmpAddress] ?? CosyncAssetUpload()
        }
        set(assetUploading) {
            let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
            URLSession.cosyncUploadMap[tmpAddress] = assetUploading
        }
    }
    
    func csClearActive() {
        let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
        URLSession.cosyncUploadMap.removeValue(forKey: tmpAddress)
    }
}

@available(macOS 10.15, *)
public enum CSUploadError: Error {
    case invalidImage
    case uploadFail
    case noUploads
    
    public var message: String {
        switch self {
        case .invalidImage:
            return "Your image is invalid"
        case .uploadFail:
            return "Whoop! Something went wrong while uploading to server"
        case .noUploads:
            return "No uploads specified"
        }
    }
}

@available(macOS 10.15, *)
public struct CSUploadItem {
    public enum MediaType {
        case image
        case video
        case audio
        case unknown
    }
    
    var path: String {
        switch type
        {
        case .image:
            return "image"
        case .video:
            return "video"
        case .audio:
            return "audio"
        case .unknown:
            return "unknown"
        }
    }
    
    var id: ObjectId
    var url: URL
    var type: MediaType = .unknown
    var noCut: Bool = false
    var smallCutSize:Int = 300
    var mediumCutSize: Int = 600
    var largeCutSize: Int = 900
    var originalSize: Int = 0
    var contentType: String = ""
    var expiration: Double = 168.0
    
    public init(id: ObjectId, url: URL, type: MediaType, expiration: Double) {
        self.id = id
        self.url = url
        self.type = type
        self.expiration = expiration
    }
}

@available(macOS 10.15, *)
public enum CSUploadState {
    case transactionStart(Int, CSTransaction)
    case assetStart(Int, Int, CosyncAssetUpload)
    case assetPogress(Int64, Int64, CosyncAssetUpload)
    case assetUploadError(Error, CosyncAssetUpload)
    case assetUploadEnd(CosyncAssetUpload)
    case assetCreated(CosyncAsset, CosyncAssetUpload)
    case transactionEnd(Int, [CosyncAsset], CSTransaction)
}

@available(macOS 10.15, *)
public typealias CSUploadCallback = (_ txId: String, _ state: CSUploadState) -> Void

@available(macOS 10.15, *)
public class CSTransaction {
    
    var txId: String = ""
    var uploadsTotal = 0
    var uploadsRemaining = 0
    var uploadsIndex: Int {
        return uploadsTotal - uploadsRemaining
    }
    var uploads: [CosyncAssetUpload] = []
    var assets: [CosyncAsset] = []
    var onUpload: CSUploadCallback
    
    init(txId: String, cb: @escaping CSUploadCallback) {
        self.txId = txId
        self.onUpload = cb
    }
    
    func start() {
        uploadsTotal = uploads.count
        uploadsRemaining = uploadsTotal
    }
    func uploadComplete(id: ObjectId, asset: CosyncAsset?) -> Bool {
        
        if let ca = asset { assets.append(ca) }
        uploads.removeAll(where: {$0._id == id})
        uploadsRemaining -= 1
        return uploads.isEmpty
    }
    
    static func findTx(txs: [CSTransaction], txId: String) -> CSTransaction? {
        return txs.first(where: {$0.txId == txId})
    }
    
    static func findUploadInTx(txs: [CSTransaction], id: ObjectId) -> (CSTransaction, CosyncAssetUpload)? {
        var ret: (CSTransaction, CosyncAssetUpload)?
        for tx in txs {
            if let upload = tx.uploads.first(where: {$0._id == id}) {
                ret = (tx, upload)
            }
        }
        return ret
    }
}

@available(macOS 10.15, *)
public class CSUploadManager: NSObject, URLSessionTaskDelegate {
    
    public static var shared = CSUploadManager()
    private var realm: Realm!
    private var app: App!
    private var userId: String!
    private var uploadToken: NotificationToken! = nil
    private var assetToken: NotificationToken! = nil
    private var uploadQueue: Deque<CosyncAssetUpload> = []
    private var activeTransactions: [CSTransaction] = []
    private var sessionId: String!
    
    @MainActor
    func configure(app: App, realm: Realm) {
        
        self.app = app
        self.realm = realm
        if let session = UIDevice.current.identifierForVendor?.uuidString {
            self.sessionId = session
        }
        
        if let user = self.app.currentUser {
            userId = user.id
            setUpAssetListener()
            setUpUploadListener()
        }
    }
    
    @MainActor
    private func setUpAssetListener() {
            
        let assetList = realm.objects(CosyncAsset.self).filter("userId == '\(userId!)'")
            
        self.assetToken = assetList.observe { (changes: RealmCollectionChange) in
                
            switch changes {
            case .initial: break
            case .update(let results, _, let insertions, _):
                for index in insertions {
                    let asset = results[index]
                    self.onAssetCreated(asset: asset)
                }
            case .error(let error):
                fatalError("\(error)")
            }
        }
    }
    
    @MainActor
    private func setUpUploadListener() {
            
        let results = realm.objects(CosyncAssetUpload.self)
                .filter("userId == '\(userId!)' && sessionId=='\(sessionId!)'")
            
        self.uploadToken = results.observe { [self] (changes: RealmCollectionChange) in
    
            switch changes {
            case .initial: break
            case .update( let results, _, _, let modifications):
                for index in modifications {
                    if results[index].status == "initialized" {
                        self.uploadAsset(assetToUpload: results[index])
                    }
                }
            case .error(let error):
                fatalError("\(error)")
            }
        }
    }
    
    @MainActor
    public func uploadAssets(uploadItems: [CSUploadItem], transactionId: String, onUpload: @escaping CSUploadCallback) throws {
        
        csLogger.info("starting upload request")
        
        if (uploadItems.isEmpty) {
            throw CSUploadError.noUploads
        }
        
        let tx = CSTransaction(txId: transactionId, cb: onUpload)
        activeTransactions.append(tx)
        
        for item in uploadItems {
            do {
                let uploadRequest = try createUploadRequest(item, transactionId: transactionId)
                uploadQueue.append(uploadRequest)
                tx.uploads.insert(uploadRequest, at: 0)
            }
            catch {
                csLogger.error("\(error.localizedDescription)")
            }
        }
        
        tx.start()
        
        onNextUpload()
        
        csLogger.info("end upload request")
    }
    
    private func createUploadRequest(_ item: CSUploadItem, transactionId: String) throws -> CosyncAssetUpload {
        
        let assetUpload = CosyncAssetUpload()
        
        if (item.type == .image) {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [item.url.absoluteString], options: nil)
            fetchResult.enumerateObjects { object, index, stop in
                let phAsset = object as PHAsset
                let resources = PHAssetResource.assetResources(for: phAsset)
                if let file = resources.first {
                    let options = PHContentEditingInputRequestOptions()
                    options.isNetworkAccessAllowed = true
                    let imageManager = PHImageManager.default()
                    let phOptions = PHImageRequestOptions()
                    phOptions.resizeMode = PHImageRequestOptionsResizeMode.exact
                    phOptions.isSynchronous = true;
                    let fileName = file.originalFilename.filter({$0 != " "})
                   
                    let contentType = fileName.mimeType()
                    
                    imageManager.requestImage(for: phAsset,
                                              targetSize: CGSize(width: phAsset.pixelWidth, height: phAsset.pixelHeight),
                                              contentMode: .aspectFit,
                                              options: phOptions,
                                              resultHandler: { image, _ in
                        
                        if  let image = image {
                            let fileSize = file.value(forKey: "fileSize") as? Int
                            assetUpload.extra = phAsset.localIdentifier
                            assetUpload.size = fileSize! + (item.noCut ? 0 : 1000 )
                            assetUpload.color = image.averageColor()
                            assetUpload.xRes = phAsset.pixelWidth
                            assetUpload.yRes = phAsset.pixelHeight
                            assetUpload.filePath = item.path + "/" + fileName
                            assetUpload.contentType = (item.contentType.isEmpty) ? contentType : item.contentType
                        }
                    })
                }
            }
        }
        else {
            let attr = try FileManager.default.attributesOfItem(atPath: item.url.path)
            let dict = attr as NSDictionary
            assetUpload.size = Int(dict.fileSize()) +  (item.noCut ? 0 : 1000 )// for additional cut
            assetUpload.extra = item.url.lastPathComponent
            assetUpload.filePath = item.path + "/" + item.url.lastPathComponent.filter({$0 != " "})
            assetUpload.contentType = (item.contentType.isEmpty) ? item.url.mimeType() : item.contentType
        }
        
        assetUpload.expirationHours = item.expiration
        assetUpload.transactionId = transactionId
        assetUpload._id = item.id
        assetUpload.userId =  self.userId
        assetUpload.sessionId = self.sessionId
        assetUpload.noCuts = item.noCut
        assetUpload.smallCutSize = item.smallCutSize
        assetUpload.mediumCutSize = item.mediumCutSize
        assetUpload.largeCutSize = item.largeCutSize
        assetUpload.originalSize = item.originalSize
        assetUpload.createdAt = Date()
        assetUpload.updatedAt = Date()
        
        csLogger.info("\(assetUpload)")

        return assetUpload
    }

    @MainActor
    private func uploadAsset(assetToUpload: CosyncAssetUpload) {
        
        let session = URLSession(configuration: .default)
        session.csActiveUpload = assetToUpload
        Task {
            do {
                csLogger.info("start upload asset")
               
                if (assetToUpload.contentType!.contains("image")) {
                    try await uploadImage(session: session, assetToUpload: assetToUpload)
                }
                else if (assetToUpload.contentType!.contains("video")){
                    try await uploadVideo(session: session, assetToUpload: assetToUpload)
                }
                else {
                    let fileUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(assetToUpload.extra)
                    try await self.uploadFile(session: session, writeUrl: assetToUpload.writeUrl!, fileUrl: fileUrl)
                }
                
                csLogger.info("end upload asset")
                
                session.csClearActive()
                onNextUpload(currentUpload: assetToUpload, status: "uploaded")
            }
            catch {
                csLogger.error("upload file fails")
                if let active = CSTransaction.findUploadInTx(txs: self.activeTransactions, id: assetToUpload._id) {
                    (active.0.onUpload)(active.0.txId, .assetUploadError(error, assetToUpload))
                }
                session.csClearActive()
                onNextUpload(currentUpload: assetToUpload, status: "failure")
            }
        }
    }
    
    @MainActor
    public func uploadImage(session: URLSession, assetToUpload: CosyncAssetUpload) async throws {
        
        csLogger.info("\(#function) start upload image")
        
        if let uploadImage = await UIImage.getImageFromFile(fileName: assetToUpload.extra) {

            var fullImageData: Data?
            if assetToUpload.contentType == "image/png" {
                fullImageData = uploadImage.pngData()
            }
            else {
                fullImageData = uploadImage.jpegData(compressionQuality: 1.0)
            }
            try await self.uploadData(session: session, data: fullImageData!, writeUrl: assetToUpload.writeUrl!, mimeType: assetToUpload.contentType!)
            try await self.uploadImageCuts(session: session, assetToUpload: assetToUpload, imageToCut: uploadImage, mimeType: assetToUpload.contentType!)
        }
        
        csLogger.info("end upload image")
    }
    
    @MainActor
    public func uploadVideo(session: URLSession, assetToUpload: CosyncAssetUpload) async throws {
        
        csLogger.info("start upload video")
       
        let writeUrl = assetToUpload.writeUrl!
        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(assetToUpload.extra)
//        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//        let fileUrl = documentPath.appendingPathComponent(assetToUpload.extra)
        
          
        try await self.uploadFile(session: session, writeUrl: writeUrl, fileUrl: fileUrl)
        let preview = fileUrl.generateVideoThumbnail()!
        let fullImageData = preview.pngData()!
        
       
        
        try await self.uploadData(session: session, data: fullImageData, writeUrl: assetToUpload.writeUrlVideoPreview!, mimeType: "image/png")
        
        try await self.uploadImageCuts(session: session, assetToUpload: assetToUpload, imageToCut: preview, mimeType: "image/png")
       
       
        try FileManager.default.removeItem(atPath: fileUrl.path) // remove local temp video file
        csLogger.info("end upload video")
        
       
    }
    
    @MainActor
    public func uploadImageCuts(session: URLSession, assetToUpload: CosyncAssetUpload, imageToCut: UIImage, mimeType: String) async throws {
        
        csLogger.info("start upload image cuts")
        
        if (assetToUpload.noCuts!) {
            return;
        }
        
        if let writeUrlSmall = assetToUpload.writeUrlSmall,
           let writeUrlMedium = assetToUpload.writeUrlMedium,
           let writeUrlLarge = assetToUpload.writeUrlLarge {
            
            let imageSmall = imageToCut.imageCut(cutSize: CGFloat(assetToUpload.smallCutSize!))
            let imageMedium = imageToCut.imageCut(cutSize: CGFloat(assetToUpload.mediumCutSize!))
            let imageLarge =  imageToCut.imageCut(cutSize: CGFloat(assetToUpload.largeCutSize!))
             
            func fullImageData(_ image: UIImage) -> Data? {
                return (mimeType == "image/png") ? image.pngData() : image.jpegData(compressionQuality: 1.0)
            }
            
            csLogger.info("start upload small cut")
            try await self.uploadData(session: session, data: fullImageData(imageSmall!)!, writeUrl: writeUrlSmall, mimeType: mimeType)
           
            csLogger.info("start upload medium cut")
            try await self.uploadData(session: session, data: fullImageData(imageMedium!)!, writeUrl: writeUrlMedium, mimeType: mimeType)
           
            csLogger.info("start upload large cut")
            try await self.uploadData(session: session, data: fullImageData(imageLarge!)!, writeUrl: writeUrlLarge, mimeType: mimeType)
        }
        
        csLogger.info("end upload image cuts")
    }
    
    public func uploadFile(session: URLSession, writeUrl: String, fileUrl: URL) async throws  {
        
        csLogger.info("start upload file")
        
        var urlRequest = URLRequest(url: URL(string: writeUrl)!)
        urlRequest.httpMethod = "PUT"
        urlRequest.setValue(fileUrl.mimeType(), forHTTPHeaderField: "content-type")
        
        let (_, response) = try await session.upload(for: urlRequest, fromFile: fileUrl, delegate: self)
        guard let taskResponse = response as? HTTPURLResponse else {
            csLogger.info("no response")
            throw CSUploadError.uploadFail
        }
        
        if taskResponse.statusCode != 200 {
            csLogger.info("response status code: \(taskResponse.statusCode)")
            throw CSUploadError.uploadFail
        }
        
        csLogger.info("end upload file")
    }
    
    public func uploadData(session: URLSession, data: Data, writeUrl: String, mimeType: String) async throws {
        
        csLogger.info("start upload data")
        
        var urlRequest = URLRequest(url: URL(string: writeUrl)!)
        urlRequest.httpMethod = "PUT"
        urlRequest.setValue(mimeType, forHTTPHeaderField: "Content-type")
        
        let (_, response) = try await session.upload(for: urlRequest, from: data, delegate: self)
         
        guard let taskResponse = response as? HTTPURLResponse else {
            csLogger.info("no response")
            throw CSUploadError.uploadFail
        }
        
        if taskResponse.statusCode != 200 {
            csLogger.info("response status code: \(taskResponse.statusCode)")
            throw CSUploadError.uploadFail
        }
        
        csLogger.info("end upload data")
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        
        let upload = session.csActiveUpload
        
        DispatchQueue.main.async {
            if let tx = CSTransaction.findTx(txs: self.activeTransactions, txId: upload.transactionId) {
                tx.onUpload(tx.txId, .assetPogress(totalBytesSent, totalBytesExpectedToSend, upload))
            }
            csLogger.info("sent: \(bytesSent) total: \(totalBytesSent) expected: \(totalBytesExpectedToSend)")
        }
    }
}

// Upload and transaction event handlers
extension CSUploadManager {
    @MainActor
    private func onAssetCreated(asset: CosyncAsset?) {
        csLogger.info("asset added")
        if let active = CSTransaction.findUploadInTx(txs: self.activeTransactions, id: asset!._id) {
            let tx = active.0
            (tx.onUpload)(tx.txId, .assetCreated(asset!, active.1))
            if (active.0.uploadComplete(id: asset!._id , asset: asset!)) {
                // If we have no more uploads then remove the transaction
                csLogger.info("transaction remove (asset)")
                self.activeTransactions.removeAll(where: {$0.txId == active.0.txId})
                (tx.onUpload)(tx.txId, .transactionEnd(tx.uploadsTotal, tx.assets, tx))
            }
        }
    }
    
    @MainActor
    private func onUploadError(upload: CosyncAssetUpload) {
        // Remove upload on error
        csLogger.info("upload error")
        if let active = CSTransaction.findUploadInTx(txs: self.activeTransactions, id: upload._id) {
            if (active.0.uploadComplete(id: upload._id, asset: nil)) {
                // If we have no more uploads then remove the transaction
                csLogger.info("transaction removed (error)")
                self.activeTransactions.removeAll(where: {$0.txId == active.0.txId})
            }
        }
    }
    
    @MainActor
    private func onNextUpload(currentUpload: CosyncAssetUpload? = nil, status: String  = "") {
        
        if let upload = currentUpload {
            if let active = CSTransaction.findUploadInTx(txs: self.activeTransactions, id: upload._id)
            {
                let tx = active.0
                (tx.onUpload)(tx.txId, .assetUploadEnd(upload))
                
                try! realm.write {
                    upload.status = status
                }
                
                var finished = true
                if uploadQueue.first(where: {$0.transactionId == upload.transactionId}) != nil
                {
                    finished = false
                }
                
                if (finished) {
                    // No more transactions
                    csLogger.info("no more uploads for tx")
                }
            }
        }
        
        if (!uploadQueue.isEmpty) {
            let nextUpload = uploadQueue.popFirst()!
            do {
                try realm.write {
                    realm.add(nextUpload)
                }
            }
            catch {
                fatalError("Unable to write data")
            }
            
            if let active = CSTransaction.findUploadInTx(txs: self.activeTransactions, id: nextUpload._id) {
                let tx = active.0
                (tx.onUpload)(tx.txId, .assetStart(tx.uploadsIndex, tx.uploadsTotal, active.1))
            }
        }
    }
}
