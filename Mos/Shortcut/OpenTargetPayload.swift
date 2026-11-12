//
//  OpenTargetPayload.swift
//  Mos
//  "打开应用 / 运行脚本 / 打开文件" 动作的持久化结构
//

import Foundation

/// 三态枚举: 配置时确定, 持久化保存, 运行时直接派发, 不依赖文件系统启发式.
enum OpenTargetKind: String, Codable {
    /// .app bundle, 通过 NSWorkspace.openApplication 启动 (支持 launch arguments).
    case application
    /// 可执行脚本或二进制, 通过 Process 运行 (支持 argv).
    case script
    /// 普通文件 (PDF / 图片 / 视频 / 文本 / etc.), 通过 NSWorkspace.open 用系统默认 app 打开.
    case file
}

/// "打开" 动作的结构化配置.
///
/// 设计目标: 自描述、可 AI 改写、可手编辑.
/// JSON 形态保持扁平, 字段名直白, 不依赖任何编码字符串.
struct OpenTargetPayload: Equatable {

    /// 文件绝对路径 (.app bundle / 脚本 / 任意文件)
    let path: String

    /// .app 的 bundle identifier; 仅 kind=.application 时非 nil.
    /// 运行时优先使用此值解析 App, 即便 .app 被移动到别处也能找到.
    let bundleID: String?

    /// 用户原始输入的参数字符串 (空字符串 = 无参数).
    /// 执行时按 shell 风格 split. 仅 .application / .script 使用; .file 忽略
    /// (NSWorkspace.open 不支持参数).
    let arguments: String

    /// 配置时确定的目标类型. 决定运行时执行路径.
    let kind: OpenTargetKind

    init(path: String, bundleID: String?, arguments: String, kind: OpenTargetKind) {
        self.path = path
        // Normalize 不变量: 只有 .application 才允许有 bundleID, 只有 .application/.script 才使用 arguments.
        // 防 hand-edited / AI rewrite 的非法组合 (e.g. .file 带 args, .script 带 bundleID) 漏到执行层.
        self.bundleID = (kind == .application) ? bundleID : nil
        self.arguments = (kind == .file) ? "" : arguments
        self.kind = kind
    }
}

// MARK: - Codable 兼容旧数据
//
// 旧版本写入字段是 `isApplication: Bool`. 新版用 `kind: OpenTargetKind` 三态.
// 解码时优先读 kind, 缺失则 fallback 读 isApplication (true → .application, false → .script).
// 编码只写 kind (不再保留 isApplication, 避免新数据双写造成歧义).
extension OpenTargetPayload: Codable {

    private enum CodingKeys: String, CodingKey {
        case path, bundleID, arguments, kind
        case isApplication  // legacy, decode only
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawPath = try c.decode(String.self, forKey: .path)
        let rawBundleID = try c.decodeIfPresent(String.self, forKey: .bundleID)
        let rawArguments = try c.decode(String.self, forKey: .arguments)
        let resolvedKind: OpenTargetKind
        if let k = try c.decodeIfPresent(OpenTargetKind.self, forKey: .kind) {
            resolvedKind = k
        } else if let isApp = try c.decodeIfPresent(Bool.self, forKey: .isApplication) {
            resolvedKind = isApp ? .application : .script
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c,
                debugDescription: "OpenTargetPayload requires either 'kind' or legacy 'isApplication'"
            )
        }
        // 走主 init 让不变量 normalize 一次 (.file 强制清空 args/bundleID, .script 强制清空 bundleID).
        self.init(path: rawPath, bundleID: rawBundleID, arguments: rawArguments, kind: resolvedKind)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
        try c.encodeIfPresent(bundleID, forKey: .bundleID)
        try c.encode(arguments, forKey: .arguments)
        try c.encode(kind, forKey: .kind)
    }
}

/// shell 风格参数切分.
///
/// 规则:
/// - 按空白字符 (空格 / 制表符 / 换行) 分隔
/// - 双引号包裹的部分原样保留 (引号本身不进入结果)
/// - 反斜杠转义紧随其后的下一个字符 (不论是否在引号内)
/// - 末尾未闭合的引号: 视作 EOF 自动闭合, 不抛错
///
/// 例: `--port=3000 "with space" \"escaped\"` → `["--port=3000", "with space", "\"escaped\""]`
enum ArgumentSplitter {

    static func split(_ raw: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = raw.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            // 反斜杠转义: 下一字符原样追加
            if scalar == "\\" {
                if let next = iterator.next() {
                    current.unicodeScalars.append(next)
                }
                continue
            }
            // 双引号: 切换状态, 引号本身不进入结果
            if scalar == "\"" {
                inQuotes.toggle()
                continue
            }
            // 引号外的空白: 切分边界
            if !inQuotes && CharacterSet.whitespaces.contains(scalar) {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
                continue
            }
            current.unicodeScalars.append(scalar)
        }
        if !current.isEmpty {
            args.append(current)
        }
        return args
    }
}
