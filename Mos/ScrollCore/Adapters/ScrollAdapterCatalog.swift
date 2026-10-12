//
//  ScrollAdapterCatalog.swift
//  Mos
//  已接入的应用滚动适配器
//

import Foundation

enum ScrollAdapterCatalog {

    static let registrations: [ScrollAdapterRegistration] = [
        ScrollAdapterRegistration(descriptor: IPhoneMirroringAdapter.descriptor) { IPhoneMirroringAdapter() },
    ]
}
