// SPDX-License-Identifier: MIT
/*
 * Read MMIO registers from /dev/mem.
 *
 * Usage:
 *   read-mmio [--width 8|32] <base-addr> <offset> [offset...]
 *
 * This is intentionally read-only. It is useful when comparing bootloader
 * display controller state with the state left by a visible Linux desktop.
 */
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static uint64_t parse_u64(const char *text)
{
	char *end = NULL;
	errno = 0;
	uint64_t value = strtoull(text, &end, 0);
	if (errno || !end || *end != '\0') {
		fprintf(stderr, "invalid integer: %s\n", text);
		exit(2);
	}
	return value;
}

int main(int argc, char **argv)
{
	int width = 32;
	int arg = 1;
	if (argc >= 4 && strcmp(argv[arg], "--width") == 0) {
		width = (int)parse_u64(argv[arg + 1]);
		if (width != 8 && width != 32) {
			fprintf(stderr, "unsupported width: %d\n", width);
			return 2;
		}
		arg += 2;
	}

	if (argc - arg < 2) {
		fprintf(stderr, "usage: %s [--width 8|32] <base-addr> <offset> [offset...]\n", argv[0]);
		return 2;
	}

	const long page_size = sysconf(_SC_PAGESIZE);
	if (page_size <= 0) {
		perror("sysconf(_SC_PAGESIZE)");
		return 1;
	}

	const uint64_t base = parse_u64(argv[arg]);
	uint64_t max_offset = 0;
	for (int i = arg + 1; i < argc; i++) {
		const uint64_t offset = parse_u64(argv[i]);
		if (offset > max_offset)
			max_offset = offset;
	}

	const uint64_t map_start = base & ~((uint64_t)page_size - 1);
	const uint64_t map_delta = base - map_start;
	const size_t access_size = width == 8 ? sizeof(uint8_t) : sizeof(uint32_t);
	const size_t map_len = (size_t)((map_delta + max_offset + access_size + page_size - 1) &
					~((uint64_t)page_size - 1));

	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) {
		perror("open(/dev/mem)");
		return 1;
	}

	volatile uint8_t *map = mmap(NULL, map_len, PROT_READ, MAP_SHARED, fd, (off_t)map_start);
	if (map == MAP_FAILED) {
		perror("mmap");
		close(fd);
		return 1;
	}

	for (int i = arg + 1; i < argc; i++) {
		const uint64_t offset = parse_u64(argv[i]);
		if (width == 8) {
			const volatile uint8_t *reg = map + map_delta + offset;
			printf("0x%010" PRIx64 "+0x%05" PRIx64 " = 0x%02" PRIx8 "\n",
			       base, offset, *reg);
		} else {
			const volatile uint32_t *reg = (const volatile uint32_t *)(map + map_delta + offset);
			printf("0x%010" PRIx64 "+0x%05" PRIx64 " = 0x%08" PRIx32 "\n",
			       base, offset, *reg);
		}
	}

	munmap((void *)map, map_len);
	close(fd);
	return 0;
}
