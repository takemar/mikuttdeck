"use strict";
var ids = [], element;
for (element of arguments[0].childNodes) {
    if (element.dataset.key == arguments[1]) {
        break;
    }
    ids.push(element.dataset.key)
}
return ids;
