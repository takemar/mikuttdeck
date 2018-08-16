"use strict";
var arr = [], element;
for (element of arguments[0].childNodes) {
    if (element.dataset.tweetId == arguments[1]) {
        break;
    }
    arr.push(element.dataset.tweetId)
}
return arr;
