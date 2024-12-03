typedef struct {
    uint32_t index;
    size_t size;
    char *data;
} nextstep_plist_t;

xpc_object_t nxp_parse_object(nextstep_plist_t *plist);