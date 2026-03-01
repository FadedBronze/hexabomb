package containers

SmallMap :: struct(S: int, K: typeid, V: typeid) {
    data: [S]struct {key: K, value: V},
    len: u16,
    empty: V,
}

sm_get :: proc(sm: ^SmallMap($S, $K, $V), key: K) -> V {
    return sm_get_ptr(sm, key)^
}

sm_get_ptr :: proc(sm: ^SmallMap($S, $K, $V), key: K) -> ^V {
    for i in 0..<sm.len {
        if sm.data[i].key == key {
            return &sm.data[i].value
        }
    }
    return &sm.empty
}

sm_set :: proc(sm: ^SmallMap($S, $K, $V), key: K, value: V) {
    ptr_val := sm_get_ptr(sm, key)

    if ptr_val != &sm.empty {
        ptr_val^ = value
        return
    }

    sm.data[sm.len].key = key
    sm.data[sm.len].value = value
    sm.len += 1
}

sm_clear :: proc(sm: ^SmallMap($S, $K, $V)) {
    sm.len = 0
}

SmallMapIterator :: struct(S: int, K: typeid, V: typeid) {
    sm: ^SmallMap(S, K, V),
    offset: u16,
}

sm_iterator :: proc(sm: ^SmallMap($S, $K, $V), offset: u16 = 0) -> SmallMapIterator(S, K, V) {
    return SmallMapIterator(S, K, V) {
        offset = offset,
        sm = sm,
    }
}

sm_iterate :: proc(smi: ^SmallMapIterator($S, $K, $V)) -> (K, V, bool) {
    if smi.offset >= smi.sm.len {
        return K{}, V{}, false
    }
    entry := smi.sm.data[smi.offset]
    smi.offset += 1
    return entry.key, entry.value, true
}

sm_peek :: proc(smi: ^SmallMapIterator($S, $K, $V)) -> (K, V, bool) {
    if smi.offset >= smi.sm.len {
        return K{}, V{}, false
    }
    entry := smi.sm.data[smi.offset]
    return entry.key, entry.value, true
}

sm_remove :: proc(smi: ^SmallMapIterator($S, $K, $V)) {
    smi.sm.data[smi.offset] = smi.sm.data[smi.sm.len-1]
    smi.sm.len -= 1
    smi.offset -= 1
}

sm_iterate_ptr :: proc(smi: ^SmallMapIterator($S, $K, $V)) -> (K, ^V, bool) {
    smi.offset += 1
    if smi.offset >= smi.sm.len {
        return K{}, &smi.sm.empty, false
    }
    entry := smi.sm.data[smi.offset]
    return entry.key, &entry.value, true
}
