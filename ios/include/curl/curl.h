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
typedef int CURLINFO;
struct curl_slist { char* data; struct curl_slist* next; };

#define CURLE_OK 0
#define CURLE_UNSUPPORTED_PROTOCOL 1
#define CURL_GLOBAL_DEFAULT 3L
#define CURLOPT_URL 10002
#define CURLOPT_USERAGENT 10018
#define CURLOPT_WRITEFUNCTION 20011
#define CURLOPT_WRITEDATA 10001
#define CURLOPT_FOLLOWLOCATION 52
#define CURLOPT_TIMEOUT 13
#define CURLOPT_CONNECTTIMEOUT 78
#define CURLOPT_HTTPHEADER 10023
#define CURLOPT_FAILONERROR 45
#define CURLOPT_SSL_VERIFYPEER 64
#define CURLINFO_RESPONSE_CODE 0x200002

CURLcode curl_global_init(long flags);
void curl_global_cleanup(void);
CURL* curl_easy_init(void);
CURLcode curl_easy_setopt(CURL* curl, CURLoption option, ...);
CURLcode curl_easy_perform(CURL* curl);
CURLcode curl_easy_getinfo(CURL* curl, CURLINFO info, ...);
void curl_easy_cleanup(CURL* curl);
const char* curl_easy_strerror(CURLcode code);
struct curl_slist* curl_slist_append(struct curl_slist* list, const char* string);
void curl_slist_free_all(struct curl_slist* list);

#ifdef __cplusplus
}
#endif