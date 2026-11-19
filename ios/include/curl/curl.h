// ios/include/curl/curl.h
// Stub leggero compatibile con ShadowRecomp/install/update_checker.cpp su iOS (evita dipendenza OpenSSL/libcurl)
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void CURL;
typedef int CURLcode;
typedef int CURLoption;

#define CURLE_OK 0
#define CURLE_UNSUPPORTED_PROTOCOL 1
#define CURLOPT_URL 10002
#define CURLOPT_USERAGENT 10018
#define CURLOPT_WRITEFUNCTION 20011
#define CURLOPT_WRITEDATA 10001
#define CURLOPT_FOLLOWLOCATION 52
#define CURLOPT_TIMEOUT 13

CURL* curl_easy_init(void);
CURLcode curl_easy_setopt(CURL* curl, CURLoption option, ...);
CURLcode curl_easy_perform(CURL* curl);
void curl_easy_cleanup(CURL* curl);
const char* curl_easy_strerror(CURLcode code);

#ifdef __cplusplus
}
#endif