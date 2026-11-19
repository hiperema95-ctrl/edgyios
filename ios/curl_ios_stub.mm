// ios/curl_ios_stub.mm
#include <curl/curl.h>

extern "C" {
CURLcode curl_global_init(long) { return CURLE_OK; }
void curl_global_cleanup(void) {}
CURL* curl_easy_init(void) { return reinterpret_cast<CURL*>(1); }
CURLcode curl_easy_setopt(CURL*, CURLoption, ...) { return CURLE_OK; }
CURLcode curl_easy_perform(CURL*) { return CURLE_UNSUPPORTED_PROTOCOL; }
CURLcode curl_easy_getinfo(CURL*, CURLINFO, ...) { return CURLE_OK; }
void curl_easy_cleanup(CURL*) {}
const char* curl_easy_strerror(CURLcode) { return "Update checker disabled on iOS sideload"; }
struct curl_slist* curl_slist_append(struct curl_slist* list, const char*) { return list; }
void curl_slist_free_all(struct curl_slist*) {}
}