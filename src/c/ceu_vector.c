#include <stdlib.h>     /* NULL */
#include <string.h>     /* memcpy */

typedef struct {
    usize max;
    usize len;
    usize ini;
    usize unit;
    u8    is_ring:    1;
    u8    is_dyn:     1;
    u8    is_freezed: 1;
    byte* buf;
} tceu_vector;

#define MIN(a,b) ((a) < (b) ? (a) : (b))
#define MAX(a,b) ((a) > (b) ? (a) : (b))

#define ceu_vector_idx(vec,idx)     ((vec)->is_ring ? (((vec)->ini + (idx)) % (vec)->max) : (idx))
#define ceu_vector_buf_get(vec,idx) (&(vec)->buf[ceu_vector_idx(vec,idx)*(vec)->unit])
#define ceu_vector_ptr(vec)         (vec)

#ifdef CEU_FEATURES_TRACE
#define ceu_vector_buf_set(vec,idx,buf,nu)      ceu_vector_buf_set_ex(vec,idx,buf,nu,CEU_TRACE(0))
#define ceu_vector_copy(dst,dst_i,src,src_i,n)  ceu_vector_copy_ex(dst,dst_i,src,src_i,n,CEU_TRACE(0))
#define ceu_vector_setmax(vec,len,freeze)       ceu_vector_setmax_ex(vec,len,freeze,CEU_TRACE(0))
#define ceu_vector_setlen_could(vec,len,grow)   ceu_vector_setlen_could_ex(vec,len,grow,CEU_TRACE(0))
#define ceu_vector_setlen(a,b,c)                ceu_vector_setlen_ex(a,b,c,CEU_TRACE(0))
#define ceu_vector_geti(a,b)                    ceu_vector_geti_ex(a,b,CEU_TRACE(0))
#else
#define ceu_vector_buf_set(vec,idx,buf,nu)      ceu_vector_buf_set_ex(vec,idx,buf,nu)
#define ceu_vector_copy(dst,dst_i,src,src_i,n)  ceu_vector_copy_ex(dst,dst_i,src,src_i,n)
#define ceu_vector_setmax(vec,len,freeze)       ceu_vector_setmax_ex(vec,len,freeze,_)
#define ceu_vector_setlen_could(vec,len,grow)   ceu_vector_setlen_could_ex(vec,len,grow)
#define ceu_vector_setlen(a,b,c)                ceu_vector_setlen_ex(a,b,c,_)
#define ceu_vector_geti(a,b)                    ceu_vector_geti_ex(a,b)
#endif

void  ceu_vector_init            (tceu_vector* vector, usize max, bool is_ring, bool is_dyn, usize unit, byte* buf);

#ifdef CEU_FEATURES_TRACE
#define ceu_vector_setmax_ex(a,b,c,d) ceu_vector_setmax_ex_(a,b,c,d)
#else
#define ceu_vector_setmax_ex(a,b,c,d) ceu_vector_setmax_ex_(a,b,c)
#endif

byte* ceu_vector_setmax_ex_      (tceu_vector* vector, usize len, bool freeze
#ifdef CEU_FEATURES_TRACE
                                 , tceu_trace trace
#endif
                                 );

int   ceu_vector_setlen_could_ex (tceu_vector* vector, usize len, bool grow
#ifdef CEU_FEATURES_TRACE
                                 , tceu_trace trace
#endif
                                 );

#ifdef CEU_FEATURES_TRACE
#define ceu_vector_setlen_ex(a,b,c,d) ceu_vector_setlen_ex_(a,b,c,d)
#else
#define ceu_vector_setlen_ex(a,b,c,d) ceu_vector_setlen_ex_(a,b,c)
#endif

void  ceu_vector_setlen_ex_      (tceu_vector* vector, usize len, bool grow
#ifdef CEU_FEATURES_TRACE
                                 , tceu_trace trace
#endif
                                 );

byte* ceu_vector_geti_ex         (tceu_vector* vector, usize idx
#ifdef CEU_FEATURES_TRACE
                                 , tceu_trace trace
#endif
                                 );

void  ceu_vector_buf_set_ex      (tceu_vector* vector, usize idx, byte* buf, usize nu
#ifdef CEU_FEATURES_TRACE
                                 , tceu_trace trace
#endif
                                 );

void  ceu_vector_copy_ex         (tceu_vector* dst, usize dst_i, tceu_vector* src, usize src_i, usize n
#ifdef CEU_FEATURES_TRACE
                                 , tceu_trace trace
#endif
                                 );

#if 0
char* ceu_vector_tochar (tceu_vector* vector);
#endif

void ceu_vector_init (tceu_vector* vector, usize max, bool is_ring,
                      bool is_dyn, usize unit, byte* buf) {
    vector->len        = 0;
    vector->max        = max;
    vector->ini        = 0;
    vector->unit       = unit;
    vector->is_dyn     = is_dyn;
    vector->is_ring    = is_ring;
    vector->is_freezed = 0;
    vector->buf        = buf;
}

byte* ceu_vector_setmax_ex_      (tceu_vector* vector, usize len, bool freeze
#ifdef CEU_FEATURES_TRACE
                                 , tceu_trace trace
#endif
                                 )
{
    ceu_assert_ex(vector->is_dyn, "static vector", trace);

    if (vector->max == len) {
        goto END;
    }

    if (len == 0) {
        /* free */
        if (vector->buf != NULL) {
            vector->max = 0;
            ceu_callback_ptr_num(CEU_CALLBACK_REALLOC, vector->buf, 0, trace);
            vector->buf = NULL;
        }
    } else {
        ceu_assert_ex(len > vector->max, "not implemented: shrinking vectors", trace);
        ceu_callback_ptr_size(CEU_CALLBACK_REALLOC,
                              vector->buf,
                              len*vector->unit,
                              trace
                             );
        vector->buf = (byte*) ceu_callback_ret.ptr;

        if (vector->is_ring && vector->ini>0) {
            /*
             * [X,Y,Z,I,J,K,###,A,B,C]       -> (grow) ->
             * [X,Y,Z,I,J,K,###,A,B,C,-,-,-] -> (1st memcpy) ->
             * [?,?,?,I,J,K,###,A,B,C,X,Y,Z] -> (2nd memmove) ->
             * [I,J,K,###,-,-,-,A,B,C,X,Y,Z]
             */
            usize dif = (len - vector->max) * vector->unit;
            memcpy (&vector->buf[vector->max],          // -,-,-
                    &vector->buf[0],                    // X,Y,Z
                    dif * vector->unit);                // 3
            memmove(&vector->buf[0],                    // X,Y,Z
                    &vector->buf[dif * vector->unit],   // I,J,K
                    vector->ini * vector->unit);        // 3
        }

        vector->max = len;
    }

    if (freeze) {
        vector->is_freezed = 1;
    }

END:
    return vector->buf;
}

int   ceu_vector_setlen_could_ex (tceu_vector* vector, usize len, bool grow
#ifdef CEU_FEATURES_TRACE
                                 , tceu_trace trace
#endif
                                 )
{
    /* must fit w/o growing */
    if (!grow) {
        if (len > vector->len) {
            return 0;
        }
    }

    /* fixed size */
    if (!vector->is_dyn || vector->is_freezed) {
        if (len > vector->max) {
            return 0;
        }

    /* variable size */
    } else {
        if (len <= vector->max) {
            /* ok */    /* len already within limits */
        } else {
            /* grow vector */
            if (ceu_vector_setmax_ex(vector,len,0,trace) == NULL) {
                if (len != 0) {
                    return 0;
                }
            }
        }
    }

    return 1;
}

void  ceu_vector_setlen_ex_      (tceu_vector* vector, usize len, bool grow
#ifdef CEU_FEATURES_TRACE
                                 , tceu_trace trace
#endif
                                 )
{
    /* must fit w/o growing */
    if (!grow) {
        ceu_assert_ex(len <= vector->len, "access out of bounds", trace);
    }

    /* fixed size */
    if (!vector->is_dyn || vector->is_freezed) {
        ceu_assert_ex(len <= vector->max, "access out of bounds", trace);

    /* variable size */
    } else {
        if (len <= vector->max) {
            /* ok */    /* len already within limits */
/* TODO: shrink memory */
        } else {
            /* grow vector */
            if (ceu_vector_setmax_ex(vector,len,0,trace) == NULL) {
                ceu_assert_ex(len==0, "access out of bounds", trace);
            }
        }
    }

    if (vector->is_ring && len<vector->len) {
        vector->ini = (vector->ini + (vector->len - len)) % vector->max;
    }

    vector->len = len;
}

byte* ceu_vector_geti_ex         (tceu_vector* vector, usize idx
#ifdef CEU_FEATURES_TRACE
                                 , tceu_trace trace
#endif
                                 )
{
    ceu_assert_ex(idx < vector->len, "access out of bounds", trace);
    return ceu_vector_buf_get(vector, idx);
}

void  ceu_vector_buf_set_ex      (tceu_vector* vector, usize idx, byte* buf, usize nu
#ifdef CEU_FEATURES_TRACE
                                 , tceu_trace trace
#endif
                                 )
{
    usize n = ((nu % vector->unit) == 0) ? nu/vector->unit : nu/vector->unit+1;
#if 0
    if (vector->len < idx+n) {
        char err[50];
        snprintf(err,50, "access out of bounds : length=%ld, index=%ld", vector->len, idx+n);
        ceu_assert_ex(0, err, file, line);
    }
#else
    ceu_assert_ex((vector->len >= idx+n), "access out of bounds", trace);
#endif

    usize k  = (vector->max - ceu_vector_idx(vector,idx));
    usize ku = k * vector->unit;

    if (vector->is_ring && ku<nu) {
        memcpy(ceu_vector_buf_get(vector,idx),   buf,    ku);
        memcpy(ceu_vector_buf_get(vector,idx+k), buf+ku, nu-ku);
    } else {
        memcpy(ceu_vector_buf_get(vector,idx), buf, nu);
    }
}

void  ceu_vector_copy_ex         (tceu_vector* dst, usize dst_i, tceu_vector* src, usize src_i, usize n
#ifdef CEU_FEATURES_TRACE
                                 , tceu_trace trace
#endif
                                 )
{
    usize unit = dst->unit;
    ceu_assert_ex((src->unit == dst->unit), "incompatible vectors", trace);

    ceu_assert_ex((src->len >= src_i+n), "access out of bounds", trace);
    ceu_vector_setlen_ex(dst, MAX(dst->len,dst_i+n), 1, trace);

    usize dif_src = MIN(n, (src->max - ceu_vector_idx(src,src_i)));
    usize dif_dst = MIN(n, (dst->max - ceu_vector_idx(dst,dst_i)));
    usize dif = MIN(dif_src, dif_dst);

    memcpy(ceu_vector_buf_get(dst,dst_i), ceu_vector_buf_get(src,src_i), dif*unit);

    dst_i += dif;
    src_i += dif;
    n -= dif;

    if (n == 0) {
        return;
    }

    if (dif_src > dif_dst) {
        dif = MIN(n, (src->max - ceu_vector_idx(src,src_i)));
        memcpy(ceu_vector_buf_get(dst,dst_i), ceu_vector_buf_get(src,src_i), dif*unit);
        dst_i += dif;
        src_i += dif;
        n -= dif;
    } else if (dif_dst > dif_src) {
        dif = MIN(n, (dst->max - ceu_vector_idx(dst,src_i)));
        memcpy(ceu_vector_buf_get(dst,dst_i), ceu_vector_buf_get(src,src_i), dif*unit);
        dst_i += dif;
        src_i += dif;
        n -= dif;
    }

    if (n == 0) {
        return;
    }

    memcpy(ceu_vector_buf_get(dst,dst_i), ceu_vector_buf_get(src,src_i), n);
}
