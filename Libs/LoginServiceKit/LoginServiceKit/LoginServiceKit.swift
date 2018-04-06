//
//  LoginServiceKit.swift
//  LoginServiceKit
//
//  Created by ShunsukeFurubayashi on 2016/04/05.
//  Copyright © 2016 Shunsuke Furubayashi. All rights reserved.
//

//
//  Some code copyright 2009 Naotaka Morimoto.
//
//	Much of this code was taken and adapted from GTMLoginItems of Google
//	Toolbox for Mac and QSBPreferenceWindowController of Quick Search Box
//	for the Mac by Google Inc.
//	This code is also released under Apache License, Version 2.0.
//

//  Copyright (c) 2008-2009 Google Inc. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are
//  met:
//
//    * Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
//  copyright notice, this list of conditions and the following disclaimer
//  in the documentation and/or other materials provided with the
//  distribution.
//    * Neither the name of Google Inc. nor the names of its
//  contributors may be used to endorse or promote products derived from
//  this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
//  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
//  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
//  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import Cocoa

public final class LoginServiceKit: NSObject {}

public extension LoginServiceKit {
    public static func isExistLoginItems(at path: String) -> Bool {
        if path.isEmpty { return false }

        let itemURL = UnsafeMutablePointer<Unmanaged<CFURL>?>.allocate(capacity: 1)
        let loginItemList = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue()
        let url = URL(fileURLWithPath: path)

        let loginItemsListSnapshot: NSArray = LSSharedFileListCopySnapshot(loginItemList, nil).takeRetainedValue()
        if let loginItems = loginItemsListSnapshot as? [LSSharedFileListItem] {
            for loginItem in loginItems {
                if LSSharedFileListItemResolve(loginItem, 0, itemURL, nil) == noErr {
                    if let memoryURL = itemURL.pointee?.takeRetainedValue() , url == memoryURL as URL {
                        return true
                    }
                }
            }
        }
        return false
    }

    public static func addLoginItems(at path: String) {
        if path.isEmpty { return }

        let loginItemList = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue()
        let url = URL(fileURLWithPath: path)

        let loginItemsListSnapshot: NSArray = LSSharedFileListCopySnapshot(loginItemList, nil).takeRetainedValue()
        let loginItems = loginItemsListSnapshot as? [LSSharedFileListItem]
        LSSharedFileListInsertItemURL(loginItemList, loginItems?.last ?? kLSSharedFileListItemBeforeFirst.takeRetainedValue(), nil, nil, url as CFURL!, nil, nil)
    }

    public static func removeLoginItems(at path: String) {
        if path.isEmpty { return }

        let itemURL = UnsafeMutablePointer<Unmanaged<CFURL>?>.allocate(capacity: 1)
        let loginItemList = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue()
        let url = URL(fileURLWithPath: path)

        let loginItemsListSnapshot: NSArray = LSSharedFileListCopySnapshot(loginItemList, nil).takeRetainedValue()
        if let loginItems = loginItemsListSnapshot as? [LSSharedFileListItem] {
            for loginItem in loginItems {
                if LSSharedFileListItemResolve(loginItem, 0, itemURL, nil) == noErr {
                    if let memoryURL = itemURL.pointee?.takeRetainedValue() , url == memoryURL as URL {
                        LSSharedFileListItemRemove(loginItemList, loginItem)
                    }
                }
            }
        }
    }
}
