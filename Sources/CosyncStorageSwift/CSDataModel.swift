//
//  CSDataModel.swift
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
//
//  Created by Tola Voeung on 3/19/23.
//  Copyright © 2020 cosync. All rights reserved.
//

import Foundation
import RealmSwift

@available(macOS 10.15, *)
public class CosyncAssetUpload: Object {
    
    @Persisted(primaryKey: true) public var _id: ObjectId
    @Persisted(indexed: true) public var userId: String = ""
    @Persisted(indexed: true) public var transactionId: String = ""
    @Persisted public var sessionId: String
    @Persisted public var extra: String = ""
    @Persisted public var filePath: String = ""
    @Persisted public var path: String = ""
    @Persisted public var expirationHours: Double = 24.0
    @Persisted public var contentType: String?
    @Persisted public var size: Int?
    @Persisted public var duration: Double?
    @Persisted public var color: String = "#000000"
    @Persisted public var xRes: Int = 0
    @Persisted public var yRes: Int = 0
    @Persisted public var smallCutSize: Int?
    @Persisted public var mediumCutSize: Int?
    @Persisted public var largeCutSize: Int?
    @Persisted public var noCuts: Bool?
    @Persisted public var originalSize: Int?
    @Persisted public var caption: String = ""
    @Persisted public var writeUrl: String?
    @Persisted public var writeUrlSmall: String?
    @Persisted public var writeUrlMedium: String?
    @Persisted public var writeUrlLarge: String?
    @Persisted public var writeUrlVideoPreview: String?
    @Persisted public var url: String?
    @Persisted public var urlSmall: String?
    @Persisted public var urlMedium: String?
    @Persisted public var urlLarge: String?
    @Persisted public var urlVideoPreview: String?
    @Persisted(indexed: true) public var status: String = "pending"
    @Persisted public var createdAt: Date?
    @Persisted public var updatedAt: Date?
}

@available(macOS 10.15, *)
public class CosyncAsset: Object {
     
    @Persisted(primaryKey: true) public var _id: ObjectId
    @Persisted(indexed: true) public var userId: String = ""
    @Persisted(indexed: true) public var sessionId: String
    @Persisted(indexed: true) public var transactionId: String = ""
    @Persisted public var path: String = ""
    @Persisted public var expirationHours: Double = 24.0
    @Persisted public var contentType: String?
    @Persisted public var size: Int?
    @Persisted public var duration: Double?
    @Persisted public var expiration: Date?
    @Persisted public var color: String = "#000000"
    @Persisted public var xRes: Int = 0
    @Persisted public var yRes: Int = 0
    @Persisted public var caption: String = ""
    @Persisted public var url: String?
    @Persisted public var urlSmall: String?
    @Persisted public var urlMedium: String?
    @Persisted public var urlLarge: String?
    @Persisted public var urlVideoPreview: String?
    @Persisted public var status: String = "active"
    @Persisted public var createdAt: Date?
    @Persisted public var updatedAt: Date?
}

@available(macOS 10.15, *)
public struct AssetModel: Codable {
    public var id: String
    public var userId: String
    public var path: String = ""
    public var expirationHours: Double = 0.0
    public var contentType: String = ""
    public var size: Int?
    public var duration: Double?
    public var expiration: Date?
    public var color: String = ""
    public var xRes: Int?
    public var yRes: Int?
    public var caption: String = ""
    public var url: String = ""
    public var urlSmall: String?
    public var urlMedium: String?
    public var urlLarge: String?
    public var urlVideoPreview: String?
    public var status: String = ""
    public var createdAt: Date?
    public var updatedAt: Date?
}

