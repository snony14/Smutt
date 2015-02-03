{-----------------------------------------------------------------------------------------
Module name: Smutt- a web server
Made by:     Tomas Möre 2014


Usage:  Pass a function of type (HTTPRequest -> IO Response) to the |serve| fucntion exported by module
        yor function is now responsible for putting together the response.
        An empty response will be treated as a |200 OK| without any content 
    
        This library uses STRICT strings internally. 



Notes for editor: Many functions are splitted into two parts, Any function with the postfix "Real"
                  has a initating function with the same name but without the postfix

------------------------------------------------------------------------------------------}
{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Server  
( serve
, module ServerOptions
) where  


import Data.Time.Clock

import Control.Concurrent
import Control.Monad
import qualified Control.Exception as E 

import System.IO
import System.IO.Error


import Network.Socket
import Network.Socket.Options 


import qualified Network.Socket.ByteString as B
import qualified Data.ByteString           as B  hiding (pack)
import qualified Data.ByteString.Char8     as B  hiding (findSubstring, elemIndex, split, break, spanEnd, dropWhile)
import qualified Data.ByteString.Internal  as BI
import qualified Data.ByteString.Builder   as BB
import qualified Data.ByteString.Lazy      as BL


import Data.Word

import Data.IORef
import Data.Maybe
import Data.Either
import Data.Monoid

import qualified ErrorResponses as ERROR

import Util
import qualified HTTP
import StatusCodes
import ServerOptions
import qualified BufferedSocket as BS 
import qualified Headers as H 

type WebThunk = (HTTP.Request -> IO HTTP.Response)

type KeepGoing = Bool




mainHTTPVersion:: ByteString
mainHTTPVersion = "HTTP/1.1"

testResponse:: ByteString
testResponse = "HTTP/1.0 200 OK\r\nContent-Length: 5\r\n\r\nPong!\r\n"

invalidReuqestResponse :: ByteString
invalidReuqestResponse = "HTTP/1.1 400 Bad Request" <> crlf




-- This function handles the response to the request. 
showExcept a = putStrLn $ "Exception: " ++ show a 

responseHandler :: (ByteString -> IO Int) -> HTTP.ParsingResult -> WebThunk -> ServerSettings ->IO KeepGoing
responseHandler send (HTTP.ParsingSuccess request) thunk settings = 
  do
    responseIN <- (thunk request) `E.catches` [ E.Handler (\ (ex :: E.ErrorCall )     -> showExcept ex >> ERROR.internalServerError)
                                              , E.Handler (\ (ex :: E.IOException)    -> showExcept ex >> ERROR.internalServerError)
                                              , E.Handler (\ (ex :: E.ArithException) -> showExcept ex >> ERROR.internalServerError)]
    dateHeader <- H.dateHeader                                            
    --response <- E.catch (thunk request)  (\ e -> putStrLn "Error!!!" >>= (\ _ -> ERROR.internalServerError))
    -- Date header for responses 
   
    let 
        -- A security check to make sure that the response wont be sent as chunked if the HTTP version isn't able to handle it
        -- A warning to the developer should be that if the chunked encoding is sent and the HTTP version isn't correct this might take up a lot of ram
        response = if (HTTP.requestVersion request) < HTTP.HTTP11 
                        then
                            case responseIN of 
                                HTTP.ChukedResponse s h b -> HTTP.FullLazyResponse s h b Nothing
                                _                    -> responseIN
                        else
                            responseIN 

        httpVersionString = HTTP.versionToString (HTTP.requestVersion request)

        (status, responseHeaders) = case response of 
                                        HTTP.FullResponse      a b  _   -> (a, b)
                                        HTTP.FullLazyResponse  a b  _ _ -> (a, b)
                                        HTTP.ChukedResponse    a b  _   -> (a, b)
                                        HTTP.HeadersResponse   a b      -> (a, b)

        statusLine                = B.concat [httpVersionString, " ", statusCodeToStr status, crlf]
        keepAlive                 = case lookup H.Connection responseHeaders of 
                                            Nothing      -> return True 
                                            Just _       -> return False
                                                    

        headerSender :: [ByteString] -> IO ()
        headerSender [] =   send crlf >> return () 
        headerSender a  =   let chunk = take 16 a
                                rest  = drop 16 a
                                readString = B.concat chunk
                            in (send readString) >> headerSender rest

        dataSender :: ByteString -> IO ()
        dataSender a = 
            do
                let chunkSize = (writeBufferSize settings)
                    chunk     = B.take chunkSize a
                    rest      = B.drop chunkSize a
                send chunk  
                if B.length rest > 0 
                    then dataSender rest
                    else return ()
                

        lazyDataSender :: [ByteString] -> IO ()
        lazyDataSender [] = return ()
        lazyDataSender (x:xs) =  dataSender x >> 
                                    lazyDataSender xs

        chunkedSender :: [ByteString] -> IO ()
        chunkedSender []     = void $ send chunkedEnd -- hex zero
        chunkedSender (x:xs) =  let chunkSize = B.length x
                                    hexSize   = intToHex (fromIntegral chunkSize)
                                in  (send hexSize) >>
                                        send x >>
                                            send crlf >>
                                                chunkedSender xs 


    case response of 
        -- If response is set to Manual we expect the developer to have taken care of everything
        HTTP.ManualResponse -> return False
        -- FullResposne asks the server to count the content and send it all. 
        -- Full response takes a full bytestring however we still send the data in smaller sizes of max 4kB each (4 KB will be set to a setting)
        HTTP.FullResponse   _ _ fullString    -> 
            do
                let contentLength = (H.ContentLength, intToByteString $ B.length fullString)
                    headers       = (contentLength : dateHeader : responseHeaders) 
                    headerList    = map H.toSendRow headers

                send statusLine 
                headerSender headerList
                dataSender fullString
                keepAlive
        -- Full LazyResponbse is the same ass FullResponse Except that we expect a list of ByteStrings
        -- A Full Lazy Response requires a content Length parameter as well
        HTTP.FullLazyResponse _ _ chunkedString contentLengthIn -> 
            do 
                let contentLength = (H.ContentLength , integerToByteString $ fromMaybe (fromIntegral (BL.length chunkedString)) contentLengthIn )
                    headers       = (contentLength : dateHeader : responseHeaders)  
                    headerList    = map H.toSendRow headers

                send statusLine 
                headerSender headerList
                lazyDataSender (BL.toChunks chunkedString)
                keepAlive
        -- ChunkedResponse is a response where we use chunks to send data. This means that for every Byrestring in the list we send one cunk.
        -- This will only work on http/1.1 clients 
        HTTP.ChukedResponse _ _ chunkedString -> 
            do  
                let headers       = ( H.chunkedHeader : dateHeader : responseHeaders)
                    headerList    = map H.toSendRow headers
                send statusLine
                headerSender headerList
                chunkedSender (BL.toChunks chunkedString)
                send crlf
                keepAlive
        HTTP.HeadersResponse _ _              ->
            do 
                let headers     = (dateHeader:responseHeaders)
                    headerList  = map H.toSendRow headers
                send statusLine 
                headerSender headerList
                keepAlive
                
responseHandler _ HTTP.ClientQuit _ _ = return False 
responseHandler s error _ _= 
  let status = case error of 
                  HTTP.URLTooLarge        -> statusCodeToStr 414 --" 414 Request-URI Too Long\n\r"
                  HTTP.InvalidVersion     -> statusCodeToStr 505 --" 505 HTTP Version Not Supported\n\r"
                  HTTP.InvalidMethod      -> statusCodeToStr 501 --" 405 Not Implemented\n\r"        
                  HTTP.HeaderLimitReached -> statusCodeToStr 413 --" 413 Request Entity Too Large\n\r"
                  HTTP.InvalidRequestLine -> statusCodeToStr 400 --" 400 Bad Request\n\r"
                  HTTP.LengthRequired     -> statusCodeToStr 411 --" 411 Length Required\n\r"
                  _                       -> statusCodeToStr 400 --" 400 Bad Request\n\r"

      response = B.concat [mainHTTPVersion, " ", status, crlf, crlf]
  in do 
      s response
      return False

-- The main thunk of the server. This code is resposible for reading the request handing it over to the "real thunk"
-- then sending the response in an appropiate manner along with closing down the socket and freeing the pointer
serverThunk :: (Socket, SockAddr) -> WebThunk -> ServerSettings -> IO ()
serverThunk fullSock@(sock, sockAddr) thunk settings = 
    do 
        #ifdef SMUTTDEBUG
        putStrLn $ "Accepted a new socket on:  " ++ (show sock) ++ " " ++ (show sockAddr)
        #endif
        -- Defining a prepared sending procedure. This procedure is sent around to all functions that might need to send data 
        let 
            send :: ByteString -> IO Int
            send outData = B.sendTo sock outData sockAddr

        bSocket    <- BS.makeBufferedSocket fullSock  (readBufferSize settings)

        --getTcpNoDelay sock >>= putStrLn . show 
        setTcpNoDelay sock True

        setRecvTimeout sock $ fromIntegral (readTimeout settings)
        setSendTimeout sock $ fromIntegral(writeTimeout settings)
        --setSocketOption sock SendBuffer  (writeBufferSize settings) 
        --setSocketOption sock RecvBuffer  (readBufferSize settings)

        case (socketKeepAlive settings) of 
            True ->  setSocketOption sock KeepAlive 1
            False -> return ()

        let readLoop = do 

                        #ifdef SMUTTDEBUG
                        timeStart    <- getCurrentTime
                        #endif

                        request      <- HTTP.readRequest bSocket send settings `E.catch` (\ e -> if isEOFError e then return HTTP.ClientQuit else E.throw e ) 
                        keepAlive    <- responseHandler send request thunk settings

                        #ifdef SMUTTDEBUG
                        timeEnd    <- getCurrentTime
                        putStrLn show $ diffUTCTime timeStart timeEnd
                        #endif 

                        if and [ not $ HTTP.connectionClosed request 
                                , HTTP.protocolCanKeepAlive request
                                , keepAlive]
                          then 
                             readLoop
                          else 
                            return ()
         
        readLoop
        sClose sock
    where 
        bufferSize = readBufferSize settings

-- The server function, Currently give it a function that will process the request and it will run a new thread from every request
serveWithSettings :: WebThunk -> ServerSettings-> IO ()
serveWithSettings thunk serverSettings = withSocketsDo $ do 

    -- create socket
    sock <- socket AF_INET Stream 0
    putStrLn $ show sock
    -- make socket immediately reusable - eases debugging.
    setSocketOption sock ReuseAddr 1

    --setSocketOption sock NoDelay 1
    
    
    -- listen on TCP port 8000
    bindSocket sock (SockAddrInet 8000 iNADDR_ANY)

    -- Tells the socket that it can have max 1000 connections
    listen sock $ maxConnections serverSettings

    let 
        maybeKeepServingRef = keepServing serverSettings
        Just keepServingRef = maybeKeepServingRef

        threadTakeover = do
                            socketData <- accept sock
                            newThread <- forkIO (serverThunk socketData thunk serverSettings)
                            return ()

        keepGoingFun   = do 
                           serveAnother <- readIORef keepServingRef
                           if serveAnother 
                                then 
                                    threadTakeover >>
                                        keepGoingFun
                                else 
                                    return ()

        choseServingMethod  = case isNothing maybeKeepServingRef of
                                    True  -> forever threadTakeover
                                    False -> keepGoingFun

    -- Makes sure that whatever happends ce close the socket. 
    choseServingMethod `E.onException` (sClose sock)

serve thunk = serveWithSettings thunk defaultSettings






