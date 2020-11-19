//
//  EnhanceArray.swift
//  Mos
//  增强数组, 使用内置字典便于快速查找
//  Created by Caldis on 2019/3/27.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Foundation

class EnhanceArray<T:Codable> {

    private var array: [T]! {
        didSet {
            updateDictionary()
            observer()
        }
    }
    private var dictionary = [String: Int]()
    private var dictionaryKey: String!
    private var observer = {()}

    public init(withArray targetArray: [T] = [], matchKey targetDictionaryKey: String = "identity", forObserver observerHandler: @escaping ()->Void = {()}) {
        setInitData(targetDictionaryKey, targetArray)
        observer = observerHandler
    }
    public init(withData targetData: Data, matchKey targetDictionaryKey: String = "identity", forObserver observerHandler: @escaping ()->Void = {()}) {
        let decoder = JSONDecoder()
        let targetArray = try! decoder.decode([T].self, from: targetData) as [T]
        setInitData(targetDictionaryKey, targetArray)
        observer = observerHandler
    }
}

/**
 * 接口
 **/
extension EnhanceArray {
    // 属性
    var count: Int {
        get {
            return array.count
        }
    }
    // 获取值
    public func get(by key: String) -> T? {
        print("GET BY", key, dictionary)
        if let index = dictionary[key] {
            return array[index]
        } else {
            return nil
        }
    }
    public func get(by index: Int) -> T {
        return array[index]
    }
    // 更新值
    public func set(by key: String, of item: T) -> EnhanceArray {
        if let index = dictionary[key] {
            array[index] = item
        }
        return self
    }
    public func set(by index: Int, of item: T) -> EnhanceArray {
        array[index] = item
        return self
    }
    public func append(_ item: T) {
        array.append(item)
    }
    // 删除值
    public func remove(from key: String) {
        if let index = dictionary[key] {
            array.remove(at: index)
        }
    }
    public func remove(at index: Int) {
        array.remove(at: index)
    }
    // 获取 JSON 数据
    public func json() -> Any? {
        let encoder = JSONEncoder()
        return try! encoder.encode(array)
    }
    // 更新内部数据 (不常用)
    public func update() {
        updateDictionary()
    }
}

/**
 * 工具
 **/
extension EnhanceArray {
    // 为了触发 didSet
    // 直接在 init 处初始化不会调用 didSet
    private func setInitData(_ targetDictionaryKey: String, _ targetArray: [T]) {
        print("setInitData", targetDictionaryKey)
        dictionaryKey = targetDictionaryKey
        array = targetArray
    }
    // 更新
    private func updateDictionary() {
        var nextDic = [String: Int]()
        for (index, item) in array.enumerated() {
            let mirror = Mirror(reflecting: item)
            for property in mirror.children {
                if let targetPropertyKey = property.label, targetPropertyKey == dictionaryKey {
                    guard let targetPropertyValue = property.value as? String else {
                        fatalError("Property of \(String(describing: dictionaryKey)) in EnhanceArray must be String Type")
                    }
                    nextDic[targetPropertyValue] = index
                    break
                }
            }
        }
        dictionary = nextDic
    }
}
