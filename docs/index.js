// 浏览器语系
var userAgentLanguage = window.navigator.language.toLowerCase()
// 页面语系
var pageLanguage = document.querySelector("html").lang
// 国际化对照表
var i18nLanguageMappingList = {
    title: {
        zh: "MOS | 一个用于在 Mac 上平滑你的鼠标滚动效果的小工具, 让你的鼠标滚轮丝滑如触控板",
        en: "MOS | A simple tool can offer the smooth scrolling and reverse the mouse scrolling direction on your Mac"
    },
    intro: {
        zh: "疯狂推荐",
        en: "Introducing"
    },
    disc: {
        zh: "一个用于在 Mac 上平滑你的鼠标滚动效果的小工具, 让你的鼠标滚轮丝爽如触控板。",
        en: "A simple tool can offer the smooth scrolling and reverse the mouse scrolling direction on your Mac"
    },
    download: {
        zh: "立马下载",
        en: "Download Now"
    },
    version: {
        zh: "版本 1.7.0, 支持 MacOS 10.11+ 系统。",
        en: "Version 1.7.0, Require macOS MacOS 10.11+. "
    },
    notes: {
        zh: "查看更新日志",
        en: "Release Notes"
    },
    star: {
        zh: "或者你可以来我们的 Github 赏个Star !",
        en: "Or Star the source code from Github !"
    },
    contact: {
        zh: "联系作者",
        en: "contact"
    },
    issue: {
        zh: "帮助支持",
        en: "Wiki"
    }
}
// 国际化页面文字
function translate(language) {
    // 目标语系 (手动指定, 默认由浏览器提供)
    var targetLanguage = language || userAgentLanguage
    // 如果目标语系与当前页面提供语系不同, 则开始翻译
    if (targetLanguage !== pageLanguage) {
        // 遍历国际化对照表
        Object.keys(i18nLanguageMappingList).forEach(function (translationKeyword) {
            // 获取每个关键字的国际化映射表
            var multiLanguages = i18nLanguageMappingList[translationKeyword]
            // 匹配语言, 如果找到对应映射, 则替换标签内原字符
            if (multiLanguages[targetLanguage]) {
                // 精确匹配 (完全相同)
                document.querySelector("#"+translationKeyword).innerText = multiLanguages[targetLanguage]
            } else if (multiLanguages[targetLanguage.substring(0, 2)]) {
                // 模糊匹配 (仅匹配目标语系的前两个字符, 也就是国家代码)
                document.querySelector("#"+translationKeyword).innerText = multiLanguages[targetLanguage.substring(0, 2)]
            }
        })
    }
}
// 开始翻译页面
translate()