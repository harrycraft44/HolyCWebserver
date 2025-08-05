
#define EASY_O_RDONLY 0
#define EASY_O_WRONLY 1
#define EASY_O_RDWR   2
#define EASY_O_CREAT  64
#define EASY_O_TRUNC  512
#define EASY_O_APPEND 1024

asm {
_EASYFSTAT::
    MOVQ    RAX, 5          // sys_fstat

    SYSCALL
    RET
}

asm {
_EASYOPEN::
    MOVQ    RAX, 2          // sys_open

    SYSCALL
    RET
}

asm {
_EASYREAD::
    MOVQ    RAX, 0          // sys_read
    SYSCALL
    RET
}

asm {
_EASYWRITE::
    MOVQ    RAX, 1          // sys_write
    SYSCALL
    RET
}

asm {
_EASYCLOSE::
    MOVQ    RAX, 3          // sys_close
    SYSCALL
    RET
}

public _extern _EASYFSTAT I64 EasyFstat(I64 fd, U8 *statbuf);
public _extern _EASYOPEN I64 EasyOpen(U8 *filename, I64 flags, I64 mode);
public _extern _EASYREAD I64 EasyRead(I64 fd, U8 *buf, I64 count);
public _extern _EASYWRITE I64 EasyWrite(I64 fd, U8 *buf, I64 count);
public _extern _EASYCLOSE I64 EasyClose(I64 fd);

I64 GetFileSize(U8 *filename) {
    I64 fd = EasyOpen(filename, EASY_O_RDONLY, 0);
    if (fd < 0) return -1;
    U8 statbuf[144]; 
    I64 res = EasyFstat(fd, statbuf);
    I64 size = -1;
    if (res == 0) {
        size = 0;
        I64 k = 0;
        for (I64 i = 0; i < 8; i++) {
            size |= statbuf[48 + i] << (8 * i);
        }
    }
    EasyClose(fd);
    return size;
}

#define EASY_O_RDONLY 0
#define EASY_O_WRONLY 1
#define EASY_O_RDWR   2
#define EASY_O_CREAT  64
#define EASY_O_TRUNC  512
#define EASY_O_APPEND 1024

I64 ReadFileToBuffer(U8 *filename, U8 *buffer, I64 maxlen) {
    I64 fd = EasyOpen(filename, EASY_O_RDONLY, 0);
    if (fd < 0) return -1;
    I64 bytes = EasyRead(fd, buffer, maxlen - 1);
    if (bytes < 0) { EasyClose(fd); return -1; }
    buffer[bytes] = 0;
    EasyClose(fd);
    return bytes;
}

I64 ReadBinaryFileToBuffer(U8 *filename, U8 *buffer, I64 maxlen) {
    I64 fd = EasyOpen(filename, EASY_O_RDONLY, 0);
    if (fd < 0) return -1;
    
    I64 total_read = 0;
    I64 chunk_size = 8192; 
    
    while (total_read < maxlen) {
        I64 to_read = maxlen - total_read;
        if (to_read > chunk_size) to_read = chunk_size;
        
        I64 bytes = EasyRead(fd, buffer + total_read, to_read);
        if (bytes < 0) { 
            EasyClose(fd); 
            return -1; 
        }
        if (bytes == 0) break; 
        
        total_read += bytes;
    }
    
    EasyClose(fd);
    return total_read;
}

// example ussage for the lazy who want this code. uwu...
// I64 fd = EasyOpen("file.txt", EASY_O_RDONLY, 0);
// I64 bytes = EasyRead(fd, buf, 1024);
// EasyClose(fd);
//
// I64 fd = EasyOpen("out.txt", EASY_O_WRONLY|EASY_O_CREAT|EASY_O_TRUNC, 0644);
// EasyWrite(fd, buf, len);
// EasyClose(fd);
