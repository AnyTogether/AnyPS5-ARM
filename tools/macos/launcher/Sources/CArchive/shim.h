// The few calls of libarchive the launcher uses to read a game's zip (GameArchives.swift). macOS
// ships libarchive in /usr/lib and its SDK carries libarchive.tbd, but not archive.h, so these
// are its declarations as libarchive 3 has them (BSD-2-Clause, https://libarchive.org).
#ifndef ANYPS5_CARCHIVE_SHIM_H
#define ANYPS5_CARCHIVE_SHIM_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

struct archive;
struct archive_entry;

#define ARCHIVE_EOF 1
#define ARCHIVE_OK 0
#define ARCHIVE_RETRY (-10)
#define ARCHIVE_WARN (-20)
#define ARCHIVE_FAILED (-25)
#define ARCHIVE_FATAL (-30)

static const mode_t AE_IFMT = 0170000;
static const mode_t AE_IFREG = 0100000;
static const mode_t AE_IFLNK = 0120000;
static const mode_t AE_IFDIR = 0040000;

struct archive *archive_read_new(void);
int archive_read_support_format_zip_seekable(struct archive *);
int archive_read_open_filename(struct archive *, const char *filename, size_t block_size);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *buffer, size_t size);
int archive_read_data_skip(struct archive *);
const char *archive_error_string(struct archive *);
int archive_read_free(struct archive *);

const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);

#endif
