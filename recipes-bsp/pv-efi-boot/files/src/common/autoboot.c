/*
 * Copyright (c) 2025-2026 Pantacor Ltd.
 * SPDX-License-Identifier: MIT
 *
 * autoboot.c — autoboot.txt parser (RPi-compatible syntax)
 *
 * Parses INI-style config with [all] and [tryboot] sections.
 * Supports: boot_partition=N, tryboot_a_b=1
 *
 * Single-pass parser that does not modify the input buffer.
 */

#include "autoboot.h"
#include "pvboot.h"

/* Compare n wide chars, return TRUE if equal */
static BOOLEAN wmatch(const CHAR16 *a, const CHAR16 *b, UINTN n)
{
    for (UINTN i = 0; i < n; i++) {
        if (a[i] != b[i])
            return FALSE;
    }
    return TRUE;
}

/* Find end of line, return pointer to char after newline (or end) */
static const CHAR16 *next_line(const CHAR16 *p)
{
    while (*p && *p != L'\n')
        p++;
    if (*p == L'\n')
        p++;
    return p;
}

/* Skip leading whitespace */
static const CHAR16 *skip_ws(const CHAR16 *p)
{
    while (*p == L' ' || *p == L'\t')
        p++;
    return p;
}

/* Measure length until delimiter char or end of line */
static UINTN span_until(const CHAR16 *p, CHAR16 delim)
{
    UINTN n = 0;
    while (p[n] && p[n] != delim && p[n] != L'\n' && p[n] != L'\r')
        n++;
    return n;
}

/* Parse a decimal number from wide string, reading up to 'len' chars */
static UINT32 parse_uint(const CHAR16 *s, UINTN len)
{
    UINT32 val = 0;
    UINTN i = 0;

    /* Skip whitespace */
    while (i < len && (s[i] == L' ' || s[i] == L'\t'))
        i++;
    while (i < len && s[i] >= L'0' && s[i] <= L'9') {
        val = val * 10 + (s[i] - L'0');
        i++;
    }
    return val;
}

/* Check if key (length klen) matches a literal */
static BOOLEAN key_eq(const CHAR16 *key, UINTN klen,
                      const CHAR16 *lit)
{
    UINTN llen = 0;
    while (lit[llen])
        llen++;
    if (klen != llen)
        return FALSE;
    return wmatch(key, lit, klen);
}

/* Apply a key=value pair to config (lengths known, no NUL needed) */
static void apply_kv(const CHAR16 *key, UINTN klen,
                     const CHAR16 *val, UINTN vlen,
                     struct autoboot_config *config)
{
    if (key_eq(key, klen, L"boot_partition"))
        config->boot_partition = parse_uint(val, vlen);
    else if (key_eq(key, klen, L"tryboot_a_b"))
        config->tryboot_a_b = (parse_uint(val, vlen) == 1);
}

/*
 * Sections of interest. SECT_NONE means we're in an unrecognized
 * section (or before any section header).
 */
enum section { SECT_NONE = 0, SECT_ALL, SECT_TRYBOOT };

static enum section match_section(const CHAR16 *name, UINTN len)
{
    if (key_eq(name, len, L"all"))
        return SECT_ALL;
    if (key_eq(name, len, L"tryboot"))
        return SECT_TRYBOOT;
    return SECT_NONE;
}

EFI_STATUS pv_parse_autoboot(EFI_FILE_PROTOCOL *root_fs,
                             BOOLEAN is_tryboot,
                             struct autoboot_config *config)
{
    EFI_FILE_PROTOCOL *file;
    EFI_STATUS status;
    CHAR8 buf8[PV_AUTOBOOT_MAX_SIZE];
    CHAR16 buf[PV_AUTOBOOT_MAX_SIZE + 1]; /* +1 for NUL terminator */
    UINTN size = sizeof(buf8);
    UINTN i, len;
    const CHAR16 *p;
    enum section cur_sect = SECT_NONE;

    /* Defaults */
    config->boot_partition = 2;
    config->tryboot_a_b = FALSE;

    status = root_fs->Open(root_fs, &file, PV_AUTOBOOT_PATH,
                           EFI_FILE_MODE_READ, 0);
    if (EFI_ERROR(status))
        return status;

    status = file->Read(file, &size, buf8);
    file->Close(file);
    if (EFI_ERROR(status))
        return status;

    /* Convert ASCII to wide chars */
    len = size;
    for (i = 0; i < len; i++)
        buf[i] = (CHAR16)buf8[i];
    buf[len] = L'\0';

    /*
     * Single-pass parse: apply [all] values immediately, then
     * [tryboot] values override if is_tryboot is set.
     */
    p = buf;
    while (*p) {
        p = skip_ws(p);

        if (*p == L'\n' || *p == L'\r') {
            /* Blank line */
            p++;
            continue;
        }

        if (*p == L'#' || *p == L';') {
            /* Comment */
            p = next_line(p);
            continue;
        }

        if (*p == L'[') {
            /* Section header: [name] */
            p++;
            const CHAR16 *sec_start = p;
            UINTN sec_len = span_until(p, L']');
            cur_sect = match_section(sec_start, sec_len);
            p = next_line(p);
            continue;
        }

        /* Key=value line */
        if (cur_sect == SECT_ALL ||
            (cur_sect == SECT_TRYBOOT && is_tryboot)) {
            const CHAR16 *key_start = p;
            UINTN key_len = span_until(p, L'=');
            p += key_len;
            if (*p == L'=') {
                p++;
                const CHAR16 *val_start = p;
                UINTN val_len = span_until(p, L'\0');
                apply_kv(key_start, key_len, val_start, val_len, config);
            }
        }

        p = next_line(p);
    }

    return EFI_SUCCESS;
}
