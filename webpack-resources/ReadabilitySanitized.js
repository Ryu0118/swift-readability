// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import { isProbablyReaderable, Readability } from "@mozilla/readability";

function postStateChanged(value) {
    webkit.messageHandlers.readabilityMessageHandler.postMessage({Type: "StateChange", Value: value});
}

if(isProbablyReaderable(document)) {
    postStateChanged("Available")
} else {
    postStateChanged("Unavailable")
}

var docStr = new XMLSerializer().serializeToString(document);
const DOMPurify = require('dompurify');
const clean = DOMPurify.sanitize(docStr, {WHOLE_DOCUMENT: true});
var doc = new DOMParser().parseFromString(clean, "text/html");
var readabilityResult;
try {
    var readability = new Readability(doc, __READABILITY_OPTION__);
    readabilityResult = readability.parse();
} catch (e) {
    readabilityResult = null;
}

webkit.messageHandlers.readabilityMessageHandler.postMessage({Type: "ContentParsed", Value: JSON.stringify(readabilityResult)});
