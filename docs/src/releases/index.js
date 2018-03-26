// 通过 Github 获取最新版本与下载链接

const endpoint = "https://api.github.com/repos/Caldis/Mos/releases/latest"
const githubVersion = document.querySelector("#githubVersion")
const githubDownloadA = document.querySelector("#headDownload")
const githubDownloadB = document.querySelector("#downloadNow")

fetch(endpoint)
    .then(res => {
        return res.json()
    }).then(json => {
        githubVersion.innerText = json.tag_name
        githubDownloadA.href = json.assets[0].browser_download_url
        githubDownloadB.href = json.assets[0].browser_download_url
    })