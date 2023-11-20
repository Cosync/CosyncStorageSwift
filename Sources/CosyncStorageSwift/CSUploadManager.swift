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

// Helper extension that allows JS formatted dates to
// be deserialized
@available(macOS 10.15, *)
extension Formatter {
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }()
}

// Extension used to track asset upload progress
@available(macOS 10.15, *)
extension URLSession {
    private static var cosyncUploadMap = [String:CSAssetUpload]()
    
    var csActiveUpload: CSAssetUpload {
        get {
            let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
            return URLSession.cosyncUploadMap[tmpAddress] ?? CSAssetUpload()
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

// Object passed to uploadAssets API that describes the upload
// being performed
@available(macOS 10.15, *)
public struct CSUploadItem {
    
    public enum MediaType {
        case image
        case video
        case audio
        case unknown
        
        func description() -> String {
            switch self {
            case .image:
                return "image"
            case .video:
                return "video"
            case .audio:
                return "audio"
            case .unknown:
                return "unkown"
            }
        }
    }
    
    // The type of ios asset we are trying to upload
    var mediaType: MediaType
    
    // The buckets in which the asset will be stored
    var path: String {
        return mediaType.description()
    }
    
    // User supplied tag that will be passed back during progress
    // callbacks. Can be useful for reconciling app asset state with
    // asset results.
    var tag: String = ""
    
    // URL to local resource
    var url: URL
    
    // The tpe of media. Determines asset processing
    //var type: MediaType = .unknown
    
    // If false skips creating additional asset cuts.
    // Only an original is saved.
    var noCut: Bool = false
    
    // Small cut size. Size value refers to the square
    // dimensions.
    var smallCutSize:Int = 300
    
    // Medium cut size. Size value refers to the square
    // dimensions.
    var mediumCutSize: Int = 600
    
    // Large cut size. Size value refers to the square
    // dimensions.
    var largeCutSize: Int = 900
    
    // Full size of the asset.
    // If not 0 then it will be resized.
    var originalSize: Int = 0
    
    // Time for which a read/write URL will be valid.
    var expirationHours: Double = 168.0
    
    public init(tag: String, url: URL, mediaType: CSUploadItem.MediaType, expiration: Double) {
        self.tag = tag
        self.url = url
        self.mediaType = mediaType
        self.expirationHours = expiration
    }
}

@available(macOS 10.15, *)
// Asset upload state object. Used to track and report
// upload state.
public struct CSAssetUpload {

    public var filePath: String = ""
    public var contentId: Int = 0
    public var contentType: String = ""
    public var expirationHours: Double = 24.0
    public var size: Int = 0
    public var duration: Double = 0.0
    public var color: String = "#000000"
    public var xRes: Int = 0
    public var yRes: Int = 0
    public var caption: String = ""
    public var extra: String = ""
    public var writeUrls: CSWriteUrls?
    public var noCuts: Bool = false
    public var transactionId = ""
    public var uploadCallback: CSUploadCallback?
    public var smallCutSize:Int = 300
    public var mediumCutSize: Int = 600
    public var largeCutSize: Int = 900
    public var originalSize: Int = 0
    public var index = 0
    public var uploadSessionCount = 0
    public var tag: String = ""
}

// Upload states that are used to communicate upload
// progress to the client.
@available(macOS 10.15, *)
public enum CSUploadState {
    // The upload session is starting. Called once.
    case transactionStart
    // An asset is about to be uploaded. Called for each asset.
    case assetStart(Int /* asset index */ , Int /* total uploads */, CSAssetUpload)
    // Reports the progress in bytes of the image upload. Called multiple
    // times for each asset.
    case assetPogress(Int64 /* bytes uploaded */, Int64 /* total bytes */, CSAssetUpload)
    // Unable to initialize asset. Nothing has been uploaded.
    case assetInitError(Error, CSUploadItem)
    // Unable to upload asset or save it
    case assetUploadError(Error, CSAssetUpload)
    // The asset has been uploaded and saved
    case assetUploadEnd(CSAssetUpload)
    // The upload session has been completed
    // Parameters are the array of uploaded assets and an
    // array of failed uploads.
    case transactionEnd([(String, CosyncAsset)], [CSUploadItem])
}

// Errors that can happen during the upload operation,
@available(macOS 10.15, *)
public enum CSUploadError: Error {
    // Unable to decode the image
    case invalidImage
    // Failed to upload or save the image
    case uploadFail
    // No uploads provided
    case noUploads
    // Unable to initialize asset upload
    case initReqError
    // Unable to create valid CosyncAsset
    case createAssetError
    
    public var message: String {
        switch self {
        case .invalidImage:
            return "Your image is invalid"
        case .uploadFail:
            return "Whoop! Something went wrong while uploading to server"
        case .noUploads:
            return "No uploads specified"
        case .initReqError:
            return "Unable to init asset"
        case .createAssetError:
            return "Unable to create asset"
        }
    }
}

// Client callback definition
@available(macOS 10.15, *)
public typealias CSUploadCallback = (_ state: CSUploadState) -> Void

// Singleton object that implements the upload API.
// The uploadAssets funtion is used to trigger and upload.
// During an upload session a callback is used
// to communicate progress and results to the client.
// See CSUpload state.
// Multiple uploads can be initiated. Each upload
// call is done in the context of its own task and
// state.
@available(macOS 10.15, *)
public class CSUploadManager: NSObject, URLSessionTaskDelegate {
    
    public static var shared = CSUploadManager()
    private var realm: Realm!
    private var app: App!
    private var userId: String!
    
    // Start the upload manager.
    // Must be called upon first access of the sigleton
    @MainActor
    public func configure(app: App, realm: Realm) {
        
        self.app = app
        self.realm = realm
    }
    
    // Upload a collection of assets
    // uploadItems - Array of CSUploadItem that contains all the
    // parameters required for the upload.
    // onUpload - Closure provided by the client that
    // communicates upload state
    @MainActor
    public func uploadAssets(uploadItems: [CSUploadItem], onUpload: @escaping CSUploadCallback) throws {
        
        csLogger.info("starting upload request")
        
        if (uploadItems.isEmpty) {
            throw CSUploadError.noUploads
        }
        
        Task {
            let callback = onUpload
            var assets: [(String, CosyncAsset)] = []
            var failedUploads: [CSUploadItem] = []
            
            // Inform the client we are about to start
            // an upload session
            onUpload(.transactionStart)
            
            var index = 0
            for item in uploadItems {
                do {
                    // 1. Create an upload arguments struct that will
                    // accumulate upload state
                    var assetArgs = try await createAssetArgs(item: item)
                    
                    // 2. Add callback and progress info.
                    assetArgs.uploadCallback = onUpload
                    assetArgs.index = index
                    assetArgs.uploadSessionCount = uploadItems.count
                    assetArgs.tag = item.tag
                    callback(.assetStart(assetArgs.index, assetArgs.uploadSessionCount, assetArgs))
                    
                    // 3. Upload and save
                    if let asset = try await self.uploadAsset(assetToUpload: assetArgs) {
                        assets.append((item.tag, asset))
                    }
                }
                catch {
                    // On error, skip the upload and move on
                    onUpload(.assetInitError(error, item))
                    failedUploads.append(item)
                    csLogger.error("\(error.localizedDescription)")
                }
                index += 1
            }
            
            // Inform the client we are done with an upload
            // session and provide any assets that resulted
            // from the operation.
            callback(.transactionEnd(assets, failedUploads))
        }
        
        csLogger.info("end upload request")
    }
    
    // Gather all of the upload parameters into a CSAssetUpload.
    // It also calls CosyncInitAsset on the server to retrieve
    // temporary write URL's
    private func createAssetArgs(item: CSUploadItem) async throws -> CSAssetUpload {
        
        var assetArgs = CSAssetUpload()
        
        if (item.mediaType == .image) {
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

                    imageManager.requestImage(for: phAsset,
                                              targetSize: CGSize(width: phAsset.pixelWidth, height: phAsset.pixelHeight),
                                              contentMode: .aspectFit,
                                              options: phOptions,
                                              resultHandler: { image, _ in
                        
                        if  let image = image {
                            let fileSize = file.value(forKey: "fileSize") as? Int
                            assetArgs.extra = phAsset.localIdentifier
                            assetArgs.size = fileSize! + (item.noCut ? 0 : 1000 )
                            assetArgs.color = image.averageColor()
                            assetArgs.xRes = phAsset.pixelWidth
                            assetArgs.yRes = phAsset.pixelHeight
                            assetArgs.filePath = item.path + "/" + fileName
                            assetArgs.contentType = fileName.mimeType()
                        }
                    })
                }
            }
        }
        else {
            let attr = try FileManager.default.attributesOfItem(atPath: item.url.path)
            let dict = attr as NSDictionary
            assetArgs.size = Int(dict.fileSize()) +  (item.noCut ? 0 : 1000)
            assetArgs.extra = item.url.lastPathComponent
            assetArgs.filePath = item.path + "/" + item.url.lastPathComponent.filter({$0 != " "})
            assetArgs.contentType = item.url.mimeType()
        }
        
        if (assetArgs.filePath.isEmpty) {
            throw CSUploadError.invalidImage
        }
        
        let user = self.app.currentUser
        let result = try await user!.functions.CosyncInitAsset([AnyBSON(assetArgs.filePath), AnyBSON(assetArgs.expirationHours), AnyBSON(assetArgs.contentType)])
        
        if let stringValue = result.stringValue {
            let decoder = JSONDecoder()
            let uploadResult = try decoder.decode(CSInitAssetResult.self, from: Data(stringValue.utf8))
            if (uploadResult.statusCode != 200) {
                throw CSUploadError.initReqError
            }
            csLogger.info("Called function 'CosynsCreateAssetUpload' and got result: \(uploadResult)")
            assetArgs.writeUrls = CSWriteUrls()
            assetArgs.writeUrls?.writeUrlSmall = uploadResult.writeUrls?.writeUrlSmall ?? ""
            assetArgs.writeUrls?.writeUrlMedium = uploadResult.writeUrls?.writeUrlMedium ?? ""
            assetArgs.writeUrls?.writeUrlLarge = uploadResult.writeUrls?.writeUrlLarge ?? ""
            assetArgs.writeUrls?.writeUrl = uploadResult.writeUrls?.writeUrl ?? ""
            assetArgs.writeUrls?.writeUrlVideoPreview = uploadResult.writeUrls?.writeUrlVideoPreview ?? ""
            assetArgs.contentId = uploadResult.contentId!
            
            assetArgs.expirationHours = item.expirationHours == 0 ? 24 : item.expirationHours
            assetArgs.noCuts = item.noCut
        }
        else {
            throw CSUploadError.initReqError
        }

        return assetArgs
    }

    // Perform the asset upload progress. It perfomrs the following.
    // 1. Check the asset type and call the associated asset processing function.
    // 2. If requested, process any cuts.
    // 3. Call the server CosyncAssetCreate. If succesful, it
    //    returns a well formed CosyncAsset with read URL's
    // 4. Commit the CosyncAsset to make it available to the client.
    private func uploadAsset(assetToUpload: CSAssetUpload) async throws -> CosyncAsset? {
        
        var asset: CosyncAsset?
        let session = URLSession(configuration: .default)
        session.csActiveUpload = assetToUpload

        // Harvest all arguments for easy reference
        let filename = assetToUpload.extra
        let writeURL = assetToUpload.writeUrls!.writeUrl
        let contentType = assetToUpload.contentType
        let writeSmallURL = assetToUpload.writeUrls!.writeUrlSmall
        let writeMediumURL = assetToUpload.writeUrls!.writeUrlMedium
        let writeLargeURL = assetToUpload.writeUrls!.writeUrlLarge
        let smallCutSize = assetToUpload.smallCutSize
        let mediumCutSize = assetToUpload.smallCutSize
        let largeCutSize = assetToUpload.smallCutSize
        let videoPreviewURL = assetToUpload.writeUrls!.writeUrlVideoPreview
        let noCuts = assetToUpload.noCuts
        
        csLogger.info("start upload asset")
        if (contentType.contains("image")) {
            
            try await uploadImage(session: session, filename: filename, writeURL: writeURL, contentType: contentType, writeURLSmall: writeSmallURL, writeURLMedium: writeMediumURL, writeURLLarge: writeLargeURL, smallCutSize: smallCutSize, mediumCutSize: mediumCutSize, largeCutSize: largeCutSize, noCuts:noCuts)
        }
        else if (contentType.contains("video")){
            
            try await uploadVideo(session: session, writeUrl: writeURL, writePreviewURL: videoPreviewURL, filename: filename, writeURLSmall: writeSmallURL, writeURLMedium: writeMediumURL, writeURLLarge: writeLargeURL, smallCutSize: smallCutSize, mediumCutSize: mediumCutSize, largeCutSize: largeCutSize, noCuts: noCuts)
        }
        else {
            let fileUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(assetToUpload.extra)
            try await self.uploadFile(session: session, writeUrl: assetToUpload.writeUrls!.writeUrl, fileUrl: fileUrl)
        }
        
        session.csClearActive()
        
        asset = try await self.saveAsset(assetToUpload)
        
        return asset
    }
    
    // Calls the server CosyncAssetCreate and commit the returned
    // CosyncAsset.
    private func saveAsset(_ assetArgs: CSAssetUpload) async throws -> CosyncAsset {
        
        var asset: CosyncAsset?
        let user = self.app.currentUser
        
        let result = try await user!.functions.CosyncCreateAsset([
                                                AnyBSON(assetArgs.filePath),
                                                AnyBSON(assetArgs.contentId),
                                                AnyBSON(assetArgs.contentType),
                                                AnyBSON(assetArgs.expirationHours),
                                                AnyBSON(assetArgs.size),
                                                AnyBSON(assetArgs.duration),
                                                AnyBSON(assetArgs.color),
                                                AnyBSON(assetArgs.xRes),
                                                AnyBSON(assetArgs.yRes),
                                                AnyBSON(assetArgs.caption),
                                                AnyBSON(assetArgs.extra)])
        if let stringValue = result.stringValue {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(Formatter.iso8601)
            let createResult = try decoder.decode(CSCreateAssetResult.self, from: Data(stringValue.utf8))
            if (createResult.statusCode != 200) {
                throw CSUploadError.createAssetError
            }
            
            // IMPORTANT: It is up to the client to commit the
            // CosyncAsset.
            DispatchQueue.main.sync {
                try! realm.write {
                    realm.add(createResult.asset)
                }
            }
            asset = createResult.asset
        }
        else {
            throw CSUploadError.createAssetError
        }
        
        return asset!
    }
    
    public func uploadImage(session: URLSession,
                            filename: String?,
                            writeURL: String?,
                            contentType: String?,
                            writeURLSmall: String?,
                            writeURLMedium: String?,
                            writeURLLarge: String?,
                            smallCutSize: Int?,
                            mediumCutSize: Int?,
                            largeCutSize: Int?,
                            noCuts: Bool?) async throws {
        
        csLogger.info("\(#function) start upload image")
        
        if let uploadImage = await UIImage.getImageFromFile(fileName: filename!) {

            var fullImageData: Data?
            if contentType == "image/png" {
                fullImageData = uploadImage.pngData()
            }
            else {
                fullImageData = uploadImage.jpegData(compressionQuality: 1.0)
            }
            try await self.uploadData(session: session, data: fullImageData!, writeUrl: writeURL!, mimeType: contentType!)
            try await self.uploadImageCuts(session: session, writeURLSmall: writeURLSmall, writeURLMedium: writeURLMedium, writeURLLarge: writeURLLarge, smallCutSize: smallCutSize, mediumCutSize: mediumCutSize, largeCutSize: largeCutSize, imageToCut: uploadImage, mimeType: contentType!, noCuts: noCuts)
        }
        
        csLogger.info("end upload image")
    }
    
    @MainActor
    private func uploadVideo(session: URLSession,
                            writeUrl: String?,
                            writePreviewURL: String?,
                            filename: String?,
                            writeURLSmall: String?,
                            writeURLMedium: String?,
                            writeURLLarge: String?,
                            smallCutSize: Int?,
                            mediumCutSize: Int?,
                            largeCutSize: Int?,
                            noCuts: Bool?) async throws {
        
        csLogger.info("start upload video")
       
        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(filename!)
          
        try await self.uploadFile(session: session, writeUrl: writeUrl!, fileUrl: fileUrl)
        let preview = fileUrl.generateVideoThumbnail()!
        let fullImageData = preview.pngData()!
        
        try await self.uploadData(session: session, data: fullImageData, writeUrl: writePreviewURL!, mimeType: "image/png")
        
        try await self.uploadImageCuts(session: session, writeURLSmall: writeURLSmall, writeURLMedium: writeURLMedium, writeURLLarge: writeURLLarge, smallCutSize: smallCutSize, mediumCutSize: mediumCutSize, largeCutSize: largeCutSize, imageToCut: preview, mimeType: "image/png", noCuts: noCuts)
       
       
        try FileManager.default.removeItem(atPath: fileUrl.path) // remove local temp video file
        csLogger.info("end upload video")
    }
    
    private func uploadImageCuts(session: URLSession,
                                writeURLSmall: String?,
                                writeURLMedium: String?,
                                writeURLLarge: String?,
                                smallCutSize: Int?,
                                mediumCutSize: Int?,
                                largeCutSize: Int?,
                                imageToCut: UIImage,
                                mimeType: String,
                                noCuts: Bool?) async throws {
        
        csLogger.info("start upload image cuts")
        
        if (noCuts!) {
            return
        }
        
        if let writeUrlSmall = writeURLSmall,
           let writeUrlMedium = writeURLMedium,
           let writeUrlLarge = writeURLLarge {
            
            let imageSmall = imageToCut.imageCut(cutSize: CGFloat(smallCutSize!))
            let imageMedium = imageToCut.imageCut(cutSize: CGFloat(mediumCutSize!))
            let imageLarge =  imageToCut.imageCut(cutSize: CGFloat(largeCutSize!))
             
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
    
    private func uploadFile(session: URLSession, writeUrl: String, fileUrl: URL) async throws  {
        
        csLogger.info("start upload file")
        
        if (writeUrl.isEmpty) {
            throw CSUploadError.uploadFail
        }
        
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
    

    private func uploadData(session: URLSession, data: Data, writeUrl: String, mimeType: String) async throws {
        
        csLogger.info("start upload data")
        
        if (writeUrl.isEmpty) {
            throw CSUploadError.uploadFail
        }
        
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
        DispatchQueue.main.async {
            let upload = session.csActiveUpload
            upload.uploadCallback!(.assetPogress(totalBytesSent, totalBytesExpectedToSend, upload))
            csLogger.info("sent: \(bytesSent) total: \(totalBytesSent) expected: \(totalBytesExpectedToSend)")
        }
    }
}
