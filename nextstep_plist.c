// Credits: https://github.com/staturnzz

#include <xpc/xpc.h>
#include <sys/stat.h>
#include "nextstep_plist.h"

#define current_char(plist) (plist->data[plist->index])

static int find_next_token(nextstep_plist_t *plist) {
    while (plist->index < plist->size) {
        char current = current_char(plist);
        plist->index++;

        switch (current) {
            case '\t' ... '\f':
            case ' ': continue;
            case '/': {
                if (plist->index < plist->size) {
                    plist->index--;
                    return 0;
                }

                switch (current_char(plist)) {
                    case '/': {
                        plist->index++;
                        while (plist->index < plist->size) {
                            if (current_char(plist) == '\n' || current_char(plist) == 'r') break;
                            plist->index++;
                        }
                    } break;
                    case '*': {
                        plist->index++;
                        while (plist->index < plist->size) {
                            current = current_char(plist);
                            plist->index++;

                            if (current == '*' && plist->index < plist->size) {
                                if (current_char(plist) == '/') {
                                    plist->index++;
                                    break;
                                }
                            }
                        }
                    } break;
                    default: {
                        plist->index--;
                        return 0;
                    } break;
                }
            } break;
            default: {
                plist->index--;
                return 0;
            } break;
        }
    }
    return -1;
}

static int validate_char(char current) {
    if ((current >= 'a' && current <= 'z') ||
        (current >= 'A' && current <= 'Z') ||
        (current >= '0' && current <= '9')) return 0;

    switch (current) {
        case '$':
        case '/':
        case ':':
        case '.':
        case '-':
        case '_': return 0;
        default: break;
    }
    return -1;
}

static char *nxp_parse_string(nextstep_plist_t *plist) {
    if (find_next_token(plist) != 0) return NULL;
    char current = current_char(plist);
    bool quoted = (current == '\'' || current == '\"');
    if (!quoted && (validate_char(current) != 0)) return NULL;

    char buf[plist->size];
    bzero(buf, plist->size);
    char *str = NULL;
    int copied = 0;

    if (quoted) plist->index++;
    for (; plist->index < plist->size; plist->index++) {
        current = current_char(plist);
        if ((quoted && (current == '\'' || current == '\"')) ||
            (!quoted && (current == ' ' || current == '\0'))) {
            buf[copied] = '\0';
            str = strdup(buf);
            break;
        }
        buf[copied++] = current;
    }
    return str;
}

static xpc_object_t nxp_parse_array(nextstep_plist_t *plist) {
    xpc_object_t array = xpc_array_create(NULL, 0);
    xpc_object_t entry = nxp_parse_object(plist);

    while (entry != NULL) {
        xpc_array_append_value(array, entry);
        xpc_release(entry);
        entry = NULL;

        if (find_next_token(plist) != 0) {
            xpc_release(array);
            return NULL;
        }

        if (current_char(plist) == ',') {
            plist->index++;
            entry = nxp_parse_object(plist);
        }
    }

    if (find_next_token(plist) != 0 || current_char(plist) != ')') {
        xpc_release(array);
        return NULL;
    }

    plist->index++;
    return array;
}

static xpc_object_t nxp_parse_dict(nextstep_plist_t *plist) {
    char *key = nxp_parse_string(plist);
    if (key == NULL) return NULL;
    xpc_object_t dict = xpc_dictionary_create(NULL, NULL, 0);

    while (key != NULL) {
        if (find_next_token(plist) != 0) {
            xpc_release(dict);
            free(key);
            return NULL;
        }

        char current = current_char(plist);
        xpc_object_t value = NULL;
        
        if (current == ';') {
            value = xpc_string_create(key);
        } else if (current == '=') {
            plist->index++;
            value = nxp_parse_object(plist);
        }

        if (value == NULL) {
            xpc_release(dict);
            free(key);
            return NULL;
        }

        xpc_dictionary_set_value(dict, key, value);
        xpc_release(value); value = NULL;
        free(key); key = NULL;
        
        if (find_next_token(plist) != 0) {
            xpc_release(dict);
            return NULL;
        }

        if (current_char(plist) == ';') {
            plist->index++;
            key = nxp_parse_string(plist);
        } else if (current_char(plist) == '}') {
            plist->index++;
            bool found_end = true;
            for (int i = plist->index; i < plist->size; i++) {
                if (plist->data[i] == ';') {
                    found_end = false;
                    break;
                }
            }
            if (found_end) return dict;
        }
    }
    return dict;
}

xpc_object_t nxp_parse_object(nextstep_plist_t *plist) {
    if (find_next_token(plist) != 0) return NULL;
    char current = current_char(plist);
    plist->index++;

    switch (current) {
        case '{': return nxp_parse_dict(plist);
        case '(': return nxp_parse_array(plist);
        case '\'':
        case '\"': {
            plist->index--;
            if (validate_char(current) == 0) {
                return nxp_parse_dict(plist);
            } else {
                char *str = nxp_parse_string(plist);
                plist->index++;
                if (str == NULL) return NULL;
                return xpc_string_create(str);
            }
        }
        default: {
            plist->index--;
            if (validate_char(current) == 0) {
                if (plist->index <= 1) {
                    return nxp_parse_dict(plist);
                } else {
                    char *str = nxp_parse_string(plist);
                    if (str == NULL) return NULL;
                    return xpc_string_create(str);
                }
            }
        }
    }
    return NULL;
}
