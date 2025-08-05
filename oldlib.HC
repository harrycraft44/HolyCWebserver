#include "easyio.HC"


I64 SendCustomHTTPResponse(I64 client_fd, U8 *status_line, U8 *content_type, U8 *body);

#define AF_INET 2
#define SOCK_STREAM 1
#define SOL_SOCKET 1
#define SO_REUSEADDR 2

asm {
_SOCKET::
    MOVQ    RAX, 41         // sys_socket
    SYSCALL
    RET
}
public _extern _SOCKET I64 Socket(I64 domain, I64 type, I64 protocol);

asm {
_BIND::
    MOVQ    RAX, 49         // sys_bind
    SYSCALL
    RET
}
public _extern _BIND I64 Bind(I64 sockfd, U8 *addr, I64 addrlen);

asm {
_LISTEN::
    MOVQ    RAX, 50         // sys_listen
    SYSCALL
    RET
}
public _extern _LISTEN I64 Listen(I64 sockfd, I64 backlog);

asm {
_ACCEPT::
    MOVQ    RAX, 43         // sys_accept
    SYSCALL
    RET
}
public _extern _ACCEPT I64 Accept(I64 sockfd, U8 *addr, I64 *addrlen);

asm {
_WRITE::
    MOVQ    RAX, 1          // sys_write
    SYSCALL
    RET
}
public _extern _WRITE I64 Write(I64 fd, U8 *buf, I64 count);

asm {
_READ::
    MOVQ    RAX, 0          // sys_read
    SYSCALL
    RET
}
public _extern _READ I64 Read(I64 fd, U8 *buf, I64 count);

asm {
_CLOSE::
    MOVQ    RAX, 3          // sys_close
    SYSCALL
    RET
}
public _extern _CLOSE I64 Close(I64 fd);

I64 WriteAll(I64 fd, U8 *buf, I64 count) {
    I64 total_written = 0;
    while (total_written < count) {
        I64 written = Write(fd, buf + total_written, count - total_written);
        if (written < 0) return -1; 
        if (written == 0) return -1; 
        total_written += written;
    }
    return total_written;
}

asm {
_SETSOCKOPT::
    MOVQ    RAX, 54         // sys_setsockopt

    SYSCALL
    RET
}
public _extern _SETSOCKOPT I64 SetSockOpt(I64 sockfd, I64 level, I64 optname, U8 *optval, I64 optlen);

I64 CreateServerSocket(I64 port) {
    I64 sockfd;
    U8 addr[16];
    
    sockfd = Socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
        printf("Socket creation failed, errno: %lld\n", sockfd);
        return -1;
    }
    printf("Socket created successfully, fd: %lld\n", sockfd);
    
    U8 reuse_bytes[8];
    reuse_bytes[0] = 1;
    reuse_bytes[1] = 0;
    reuse_bytes[2] = 0;
    reuse_bytes[3] = 0;
    reuse_bytes[4] = 0;
    reuse_bytes[5] = 0;
    reuse_bytes[6] = 0;
    reuse_bytes[7] = 0;
    if (SetSockOpt(sockfd, SOL_SOCKET, SO_REUSEADDR, reuse_bytes, 4) < 0) {
        printf("Warning: Failed to set SO_REUSEADDR, continuing anyway...\n");
    } else {
        printf("SO_REUSEADDR set successfully\n");
    }
    
    for (I64 i = 0; i < 16; ++i) addr[i] = 0;
    
    addr[0] = AF_INET;      
    addr[1] = 0;            
    addr[2] = (port >> 8) & 0xFF;  
    addr[3] = port & 0xFF;          

    
    printf("Binding to port %lld...\n", port);
    

    I64 bind_result = Bind(sockfd, addr, 16);
    if (bind_result < 0) {
        printf("Bind failed with error: %lld\n", bind_result);
        printf("Try a different port or wait a moment\n");
        Close(sockfd);
        return -1;
    }
    printf("Bind successful\n");
    
    if (Listen(sockfd, 10) < 0) {
        printf("Listen failed\n");
        Close(sockfd);
        return -1;
    }
    printf("Listen successful\n");
    
    return sockfd;
}

I64 SendHTTPResponse(I64 client_fd, U8 *body) {
    return SendCustomHTTPResponse(client_fd, "HTTP/1.1 200 OK\r\n", "Content-Type: text/html; charset=UTF-8", body);
}

I64 Send404Response(I64 client_fd, U8 *body) {
    return SendCustomHTTPResponse(client_fd, "HTTP/1.1 404 Not Found\r\n", "Content-Type: text/html; charset=UTF-8", body);
}

I64 Send503Response(I64 client_fd, U8 *body) {
    return SendCustomHTTPResponse(client_fd, "HTTP/1.1 503 Service Unavailable\r\n", "Content-Type: text/html; charset=UTF-8", body);
}



I64 SendCustomHTTPResponse(I64 client_fd, U8 *status_line, U8 *content_type, U8 *body) {
    I64 body_len = 0;
    while (body[body_len] != 0) body_len++;

    U8 content_length_str[32];
    I64 n = body_len;
    I64 i = 0;
    if (n == 0) {
        content_length_str[i++] = '0';
    } else {
        U8 temp[32];
        I64 j = 0;
        while (n > 0) {
            temp[j++] = '0' + (n % 10);
            n /= 10;
        }
        while (j > 0) {
            content_length_str[i++] = temp[--j];
        }
    }
    content_length_str[i] = 0;

    U8 header[1024];
    I64 len = 0;
    I64 k = 0;

    printf("DEBUG: Status line: '%s'\n", status_line);
    while (status_line[k] != 0) header[len++] = status_line[k++];
    printf("DEBUG: After status line copy, len = %lld\n", len);
    
    U8 *server = "Server: HolyC-WebServer/1.0\r\n";
    k = 0;
    while (server[k] != 0) header[len++] = server[k++];
    
    k = 0;
    while (content_type[k] != 0) header[len++] = content_type[k++];
    header[len++] = '\r'; header[len++] = '\n';
    
    U8 *cl = "Content-Length: ";
    k = 0;
    while (cl[k] != 0) header[len++] = cl[k++];
    k = 0;
    while (content_length_str[k] != 0) header[len++] = content_length_str[k++];
    header[len++] = '\r'; header[len++] = '\n';
    
    U8 *cache = "Cache-Control: no-cache\r\n";
    k = 0;
    while (cache[k] != 0) header[len++] = cache[k++];
    
    U8 *conn = "Connection: close\r\n";
    k = 0;
    while (conn[k] != 0) header[len++] = conn[k++];
    
    header[len++] = '\r'; header[len++] = '\n';

    printf("Sending %lld byte response with proxy-friendly headers\n", body_len);

    if (WriteAll(client_fd, header, len) < 0) return -1;
    if (WriteAll(client_fd, body, body_len) < 0) return -1;

    return 0;
}


I64 SendData(I64 client_fd, I64 status, U8 *content_type, U8 *body) {
    U8 status_line[64];
    I64 pos = 0;
    U8 *base = "HTTP/1.1 ";
    while (base[pos]) { status_line[pos] = base[pos]; pos++; }

    I64 code = status;
    U8 codebuf[8];
    I64 cpos = 0;
    if (code == 0) codebuf[cpos++] = '0';
    else {
        I64 t = code, digits = 0;
        while (t) { t /= 10; digits++; }
        for (I64 d = digits-1; d >= 0; d--) {
            codebuf[d] = '0' + (code % 10);
            code /= 10;
        }
        cpos = digits;
    }
    for (I64 i = 0; i < cpos; i++) status_line[pos++] = codebuf[i];

    U8 *msg = " OK";
    if (status == 404) msg = " Not Found";
    if (status == 500) msg = " Internal Server Error";
    if (status == 503) msg = " Service Unavailable";
    I64 m = 0; while (msg[m]) status_line[pos++] = msg[m++];
    status_line[pos++] = '\r'; status_line[pos++] = '\n';
    status_line[pos] = 0;
    
    U8 ct_formatted[128];
    I64 ct_pos = 0;
    U8 *ct_prefix = "Content-Type: ";
    I64 prefix_idx = 0;
    while (ct_prefix[prefix_idx]) ct_formatted[ct_pos++] = ct_prefix[prefix_idx++];
    I64 ct_idx = 0;
    while (content_type[ct_idx]) ct_formatted[ct_pos++] = content_type[ct_idx++];
    ct_formatted[ct_pos] = 0;
    
    return SendCustomHTTPResponse(client_fd, status_line, ct_formatted, body);
}

I64 SendHTML(I64 client_fd, U8 *html, I64 status) {
    return SendData(client_fd, status, "text/html; charset=UTF-8", html);
}

I64 SendFile(I64 client_fd, U8 *filepath, U8 *content_type, I64 status) {
    U8 filebuf[4194304]; 
    I64 filelen = -1;
    
    I64 is_binary = 0;
    if (content_type) {

        U8 *ct = content_type;
        if ((ct[0] == 'i' && ct[1] == 'm' && ct[2] == 'a' && ct[3] == 'g' && ct[4] == 'e') ||
            (ct[0] == 'a' && ct[1] == 'p' && ct[2] == 'p' && ct[3] == 'l' && ct[4] == 'i' && ct[5] == 'c' && ct[6] == 'a' && ct[7] == 't' && ct[8] == 'i' && ct[9] == 'o' && ct[10] == 'n')) {
            is_binary = 1;
        }
    }
    
    if (is_binary) {
        filelen = ReadBinaryFileToBuffer(filepath, filebuf, sizeof(filebuf));
    } else {
        filelen = ReadFileToBuffer(filepath, filebuf, sizeof(filebuf));
    }
    
    if (filelen <= 0) return SendData(client_fd, 404, "text/html; charset=UTF-8", "<h1>404 Not Found</h1>");
    
    U8 status_line[64];
    I64 pos = 0;
    U8 *base = "HTTP/1.1 ";
    while (base[pos]) { status_line[pos] = base[pos]; pos++; }
    I64 code = status;
    U8 codebuf[8];
    I64 cpos = 0;
    if (code == 0) codebuf[cpos++] = '0';
    else {
        I64 t = code, digits = 0;
        while (t) { t /= 10; digits++; }
        for (I64 d = digits-1; d >= 0; d--) {
            codebuf[d] = '0' + (code % 10);
            code /= 10;
        }
        cpos = digits;
    }
    for (I64 i = 0; i < cpos; i++) status_line[pos++] = codebuf[i];
    U8 *msg = " OK";
    if (status == 404) msg = " Not Found";
    if (status == 500) msg = " Internal Server Error";
    I64 m = 0; while (msg[m]) status_line[pos++] = msg[m++];
    status_line[pos++] = '\r'; status_line[pos++] = '\n';
    status_line[pos] = 0;
    
    U8 ct_formatted[128];
    I64 ct_pos = 0;
    U8 *ct_prefix = "Content-Type: ";
    I64 prefix_idx = 0;
    while (ct_prefix[prefix_idx]) ct_formatted[ct_pos++] = ct_prefix[prefix_idx++];
    I64 ct_idx = 0;
    while (content_type[ct_idx]) ct_formatted[ct_pos++] = content_type[ct_idx++];
    ct_formatted[ct_pos] = 0;
    
    I64 body_len = filelen;

    U8 content_length_str[32];
    I64 n = body_len;
    I64 i = 0;
    if (n == 0) {
        content_length_str[i++] = '0';
    } else {
        U8 temp[32];
        I64 j = 0;
        while (n > 0) {
            temp[j++] = '0' + (n % 10);
            n /= 10;
        }
        while (j > 0) {
            content_length_str[i++] = temp[--j];
        }
    }
    content_length_str[i] = 0;

    U8 header[1024];
    I64 len = 0;
    I64 k = 0;

    while (status_line[k] != 0) header[len++] = status_line[k++];
    
    U8 *server = "Server: HolyC-WebServer/1.0\r\n";
    k = 0;
    while (server[k] != 0) header[len++] = server[k++];
    
    k = 0;
    while (ct_formatted[k] != 0) header[len++] = ct_formatted[k++];
    header[len++] = '\r'; header[len++] = '\n';
    
    U8 *cl = "Content-Length: ";
    k = 0;
    while (cl[k] != 0) header[len++] = cl[k++];
    k = 0;
    while (content_length_str[k] != 0) header[len++] = content_length_str[k++];
    header[len++] = '\r'; header[len++] = '\n';
    
    U8 *cache = "Cache-Control: no-cache\r\n";
    k = 0;
    while (cache[k] != 0) header[len++] = cache[k++];
    
    U8 *conn = "Connection: close\r\n";
    k = 0;
    while (conn[k] != 0) header[len++] = conn[k++];
    
    header[len++] = '\r'; header[len++] = '\n';

    printf("Sending %lld byte file response with proxy-friendly headers\n", body_len);

    if (WriteAll(client_fd, header, len) < 0) return -1;
    if (WriteAll(client_fd, filebuf, filelen) < 0) return -1;

    return 0;
}