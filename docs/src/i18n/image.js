// 图片国际化
// HTML 绑定对应 ID, 此处查找 ID, 将预设的图片链接替换入内

(function () {
    // 浏览器语系
    var userAgentLanguage = window.navigator.language.toLowerCase()
    // 页面语系
    var pageLanguage = document.querySelector("html").lang
    // 国际化对照表
    var i18nLanguageMappingList = {
        detailImageA: {
            zh: "./resources/image/cn/PreferencesGeneral.png",
            en: "./resources/image/en/PreferencesGeneral.png"
        },
        detailImageB: {
            zh: "./resources/image/cn/PreferencesAdvanced.png",
            en: "./resources/image/en/PreferencesAdvanced.png"
        },
        detailImageC: {
            zh: "./resources/image/cn/PreferencesExceptionFull.png",
            en: "./resources/image/en/PreferencesExceptionFull.png"
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
                    document.querySelector("#"+translationKeyword).src = multiLanguages[targetLanguage]
                } else if (multiLanguages[targetLanguage.substring(0, 2)]) {
                    // 模糊匹配 (仅匹配目标语系的前两个字符, 也就是国家代码)
                    document.querySelector("#"+translationKeyword).src = multiLanguages[targetLanguage.substring(0, 2)]
                }
            })
        }
    }
    // 开始翻译页面
    translate()
})()