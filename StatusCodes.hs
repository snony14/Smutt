{-----------------------------------------------------------------------------------------
Module name: Status Codes
Made by:     Tomas Möre 2015
------------------------------------------------------------------------------------------}

{-# LANGUAGE OverloadedStrings #-}
module StatusCodes where

import Data.ByteString 

statusCodeToStr ::  Int -> ByteString
statusCodeToStr 100 = "100 Continue"
statusCodeToStr 101 = "101 Switching Protocols"
statusCodeToStr 103 = "103 Checkpoint"
statusCodeToStr 200 = "200 OK"
statusCodeToStr 201 = "201 Created"
statusCodeToStr 202 = "202 Accepted"
statusCodeToStr 203 = "203 Non-Authoritative Information"
statusCodeToStr 204 = "204 No Content"
statusCodeToStr 205 = "205 Reset Content"
statusCodeToStr 206 = "206 Partial Content"
statusCodeToStr 300 = "300 Multiple Choices"
statusCodeToStr 301 = "301 Moved Permanently"
statusCodeToStr 302 = "302 Found"
statusCodeToStr 303 = "303 See Other"
statusCodeToStr 304 = "304 Not Modified"
statusCodeToStr 306 = "306 Switch Proxy"
statusCodeToStr 307 = "307 Temporary Redirect"
statusCodeToStr 308 = "308 Resume Incomplete"
statusCodeToStr 400 = "400 Bad Request"
statusCodeToStr 401 = "401 Unauthorized"
statusCodeToStr 402 = "402 Payment Required"
statusCodeToStr 403 = "403 Forbidden"
statusCodeToStr 404 = "404 Not Found"
statusCodeToStr 405 = "405 Method Not Allowed"
statusCodeToStr 406 = "406 Not Acceptable"
statusCodeToStr 407 = "407 Proxy Authentication Required"
statusCodeToStr 408 = "408 Request Timeout"
statusCodeToStr 409 = "409 Conflict"
statusCodeToStr 410 = "410 Gone"
statusCodeToStr 411 = "411 Length Required"
statusCodeToStr 412 = "412 Precondition Failed"
statusCodeToStr 413 = "413 Request Entity Too Large"
statusCodeToStr 414 = "414 Request-URI Too Long"
statusCodeToStr 415 = "415 Unsupported Media Type"
statusCodeToStr 416 = "416 Requested Range Not Satisfiable"
statusCodeToStr 417 = "417 Expectation Failed"
statusCodeToStr 500 = "500 Internal Server Error"
statusCodeToStr 501 = "501 Not Implemented"
statusCodeToStr 502 = "502 Bad Gateway"
statusCodeToStr 503 = "503 Service Unavailable"
statusCodeToStr 504 = "504 Gateway Timeout"
statusCodeToStr 505 = "505 HTTP Version Not Supported"
statusCodeToStr 511 = "511 Network Authentication Required"
 
