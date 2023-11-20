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
// Cosync asset Realm object
public class CosyncAsset: Object, Codable {
    @Persisted(primaryKey: true) public var _id: ObjectId
    @Persisted(indexed: true) public var userId: String = ""
    @Persisted public var path: String = ""
    @Persisted public var extra: String?
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
// Urls from CosyncInitAsset
public struct CSWriteUrls: Codable {
    public var writeUrl:String = ""
    public var writeUrlLarge:String?
    public var writeUrlMedium:String?
    public var writeUrlSmall:String?
    public var writeUrlVideoPreview:String?
}

@available(macOS 10.15, *)
// Return object from CosyncInitAsset
public struct CSInitAssetResult: Codable {
    public var statusCode: Int
    public var contentId: Int?
    public var writeUrls: CSWriteUrls?
}

@available(macOS 10.15, *)
// Return object from CosyncCreateAsset
public struct CSCreateAssetResult: Codable {
    public var statusCode: Int
    public var asset: CosyncAsset
}


