// From:
// https://codepen.io/andrit/pen/kkVxag

var docStyle = document.documentElement.style
var aElem = document.querySelector('.parallaxButton')
var boundingClientRect = aElem.getBoundingClientRect()

window.onresize = function (e) {
    boundingClientRect = aElem.getBoundingClientRect()
}
window.onscroll = function (e) {
    boundingClientRect = aElem.getBoundingClientRect()
}

aElem.onmousemove = function(e) {
    const x = e.clientX - boundingClientRect.left
    const y = e.clientY - boundingClientRect.top
    const xc = boundingClientRect.width/2
    const yc = boundingClientRect.height/2
    const dx = x - xc
    const dy = y - yc
    docStyle.setProperty('--rx', `${ dy/-1 }deg`)
    docStyle.setProperty('--ry', `${ dx/10 }deg`)
}

aElem.onmouseleave = function(e) {
    docStyle.setProperty('--ty', '0')
    docStyle.setProperty('--rx', '0')
    docStyle.setProperty('--ry', '0')
}

aElem.onmousedown = function(e) {
    docStyle.setProperty('--tz', '-25px')
}

document.body.onmouseup = function(e) {
    docStyle.setProperty('--tz', '-12px')
}