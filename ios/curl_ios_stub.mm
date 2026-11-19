// ios/curl_ios_stub.mm
#include <curl/curl.h>

extern "C" {
CURL* curl_easy_init(void) { return reinterpret_cast<CURL*>(1); }
CURLcode curl_easy_setopt(CURL*, CURLoption, ...) { return CURLE_OK; }
CURLcode curl_easy_perform(CURL*) { return CURLE_UNSUPPORTED_PROTOCOL; }
void curl_easy_cleanup(CURL*) {}
const char* curl_easy_strerror(CURLcode) { return "Update checker disabled on iOS sideload"; }
}