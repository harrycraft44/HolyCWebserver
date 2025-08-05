// a production level ready http server im lying but its in HolyC so cant hate it
#include "oldlib.HC"
#include "easyio.HC"

//     config
// ============================================================================

#define SERVER_PORT 8284
#define MAX_REQUEST_SIZE 2048
#define MAX_PATH_LENGTH 255
#define MAX_METHOD_LENGTH 16

U8 homepage[] = "<!DOCTYPE html><html ><head><title>Welcome to HolyC Web Server</title></head><body><h1>Nothing here yet</h1><p></p></body></html>";

U8 not_found_page[] = "<!DOCTYPE html><html><head><title>404 - Page Not Found</title><style>body { font-family: Arial, sans-serif; margin: 40px; background: #f0f0f0; } .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); text-align: center; } h1 { color: #e74c3c; } p { color: #666; line-height: 1.6; } a { color: #3498db; text-decoration: none; } a:hover { text-decoration: underline; }</style></head><body><div class='container'><h1>404 - Page Not Found</h1><p>Sorry, the page you're looking for doesn't exist.</p><p><a href='/'>&larr; Go back to homepage</a></p></div></body></html>";

U8 rate_limit_page[] = "<!DOCTYPE html><html><head><title>503 - Service Temporarily Unavailable</title><style>body { font-family: Arial, sans-serif; margin: 40px; background: #f0f0f0; } .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); text-align: center; } h1 { color: #f39c12; } p { color: #666; line-height: 1.6; } a { color: #3498db; text-decoration: none; } a:hover { text-decoration: underline; }</style></head><body><div class='container'><h1>503 - Service Temporarily Unavailable</h1><p>Server is currently processing another request. Please try again in a moment.</p><p><a href='/'>&larr; Try again</a></p></div></body></html>";

// Rate limiting  
I64 isprocessingrequest;

//  UTILITY FUNCTIONS
// ===============================================


I64 IsSecurePath(U8 *path) {
    I64 i = 0;
    while (path[i] != 0) {
        // Check for "../" sequences
        if (path[i] == '.' && path[i+1] == '.' && path[i+2] == '/') {
            return 0; // Unsafe path
        }
        // Check for "/.." at end or followed by /
        if (path[i] == '/' && path[i+1] == '.' && path[i+2] == '.' && 
            (path[i+3] == 0 || path[i+3] == '/')) {
            return 0; // Unsafe path
        }
        // Prevent absolute paths outside current directory
        if (i == 0 && path[i] == '/') {
            // Allow only relative paths or specific allowed absolute paths
            // For now, block all absolute paths except our specific ones
        }
        i++;
    }
    return 1; // Safe path
}

// len of string
I64 GetStringLength(U8 *text) {
    I64 length = 0;
    while (text[length] != 0) {
        length++;
    }
    return length;
}


I64 CompareStrings(U8 *first, U8 *second) {
    I64 index = 0;
    while (first[index] != 0 && second[index] != 0) {
        if (first[index] != second[index]) {
            return first[index] - second[index];
        }
        index++;
    }
    return first[index] - second[index];
}

//    request parsing
// ====================================================



// parse the http data to get the method and path with security checks
I64 ParseHttpRequest(U8 *request_data, U8 **method, U8 **path) {
    *method = request_data;
    *path = 0;
    
    I64 position = 0;
    I64 method_length = 0;
    
    // Security: Check method length and validate characters
    while (request_data[position] != ' ' && request_data[position] != 0 && position < MAX_REQUEST_SIZE) {
        if (method_length >= MAX_METHOD_LENGTH) {
            return -1; // Method too long
        }
        // Only allow uppercase letters for HTTP methods
        if (request_data[position] < 'A' || request_data[position] > 'Z') {
            return -1; // Invalid method character
        }
        position++;
        method_length++;
    }
    
    if (request_data[position] != ' ' || method_length == 0) {
        return -1; // Invalid request format
    }
    
    request_data[position] = 0;
    position++;
    
    // Skip multiple spaces
    while (request_data[position] == ' ' && position < MAX_REQUEST_SIZE) {
        position++;
    }
    
    if (position >= MAX_REQUEST_SIZE) {
        return -1; // Request too long
    }

    *path = request_data + position;
    I64 path_length = 0;
    
    // Security: Check path length and basic validation
    while (request_data[position] != ' ' && request_data[position] != 0 && position < MAX_REQUEST_SIZE) {
        if (path_length >= MAX_PATH_LENGTH) {
            return -1; // Path too long
        }
        position++;
        path_length++;
    }
    
    if (path_length == 0) {
        return -1; // Empty path
    }
    
    if (request_data[position] == ' ') {
        request_data[position] = 0;
    }
    
    return 0; 
}

//  CLIENT handling 
// ================================================



U0 ProcessClientRequest(I64 client_socket) {
    U8 request_buffer[MAX_REQUEST_SIZE];
    U8 *http_method, *requested_path;
    
    printf("New client connected! Reading their request...\n");
    
    isprocessingrequest = 1;
    
    I64 bytes_received = Read(client_socket, request_buffer, sizeof(request_buffer) - 1);
    
    if (bytes_received <= 0) {
        printf(" Failed to read request (received %lld bytes)\n", bytes_received);
        isprocessingrequest = 0; // Clear flag on error
        return;
    }
    
    request_buffer[bytes_received] = 0;
    printf("Received %lld bytes from client\n", bytes_received);
    
    if (ParseHttpRequest(request_buffer, &http_method, &requested_path) < 0) {
        printf("Invalid HTTP request format - sending 404\n");
        Send404Response(client_socket, not_found_page);
        isprocessingrequest = 0; // Clear flag on error
        return;
    }
    
    printf("Request: %s %s\n", http_method, requested_path);
    
    if (CompareStrings(http_method, "GET") == 0) {
        if (requested_path && CompareStrings(requested_path, "/") == 0) {
            // Security: Validate file path
            if (!IsSecurePath("index.html")) {
                printf("SECURITY: Blocked unsafe path attempt\n");
                Send404Response(client_socket, not_found_page);
                isprocessingrequest = 0;
                return;
            }
            I64 result = SendFile(client_socket, "index.html", "text/html; charset=UTF-8", 200);
            if (result < 0) {
                printf("index.html not found, sending built-in homepage\n");
                SendHTML(client_socket, homepage, 200);
            } else {
                printf("index.html sent successfully!\n");
            }
        } else if (requested_path && CompareStrings(requested_path, "/about") == 0) {
            // Security: Validate file path
            if (!IsSecurePath("about.html")) {
                printf("SECURITY: Blocked unsafe path attempt\n");
                Send404Response(client_socket, not_found_page);
                isprocessingrequest = 0;
                return;
            }
            I64 result = SendFile(client_socket, "about.html", "text/html; charset=UTF-8", 200);
            if (result < 0) {
                printf("about.html not found, sending homepage\n");
                SendHTML(client_socket, homepage, 200);
            } else {
                printf("about.html sent successfully!\n");
            }
        } else if (requested_path && requested_path[0] == '/' && requested_path[1] == 's' && requested_path[2] == 't' && requested_path[3] == 'a' && requested_path[4] == 't' && requested_path[5] == 'u' && requested_path[6] == 's' && requested_path[7] == '/' && requested_path[8] != 0) {
            U8 *status_filename = requested_path + 8;
            U8 status_filepath[256];
            I64 i = 0;
            
            // Security: Ensure we don't overflow the buffer
            I64 max_buffer_size = sizeof(status_filepath) - 1; // Reserve space for null terminator
            
            // status prefix in to array
            if (i + 7 >= max_buffer_size) {
                printf("SECURITY: Status path buffer too small\n");
                Send404Response(client_socket, not_found_page);
                isprocessingrequest = 0;
                return;
            }
            status_filepath[i++] = 's';
            status_filepath[i++] = 't';
            status_filepath[i++] = 'a';
            status_filepath[i++] = 't';
            status_filepath[i++] = 'u';
            status_filepath[i++] = 's';
            status_filepath[i++] = '/';

            // checking if the file name is valid with strict bounds checking
            I64 j = 0;
            I64 max_filename_chars = 50; // Reasonable limit for status filenames
            while (status_filename[j] != 0 && j < max_filename_chars && i < max_buffer_size - 5) { // Reserve 5 chars for .png + null
                
                U8 c = status_filename[j];
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.') {
                    status_filepath[i++] = c;
                    j++;
                } else {
                    printf("SECURITY: Invalid character in status filename: %s\n", requested_path);
                    Send404Response(client_socket, not_found_page);
                    isprocessingrequest = 0;
                    return;
                }
            }
            
            // cheeck if we hit the limits
            if (j >= max_filename_chars) {
                printf("SECURITY: Status filename too long: %s\n", requested_path);
                Send404Response(client_socket, not_found_page);
                isprocessingrequest = 0;
                return;
            }
            
            // check if .png is needed with bounds checking
            if (i >= 4 && status_filepath[i-4] == '.' && status_filepath[i-3] == 'p' && status_filepath[i-2] == 'n' && status_filepath[i-1] == 'g') {
                // Already has .png extension
            } else if (i + 4 < max_buffer_size) {
                status_filepath[i++] = '.';
                status_filepath[i++] = 'p';
                status_filepath[i++] = 'n';
                status_filepath[i++] = 'g';
            } else {
                printf("SECURITY: Status filename too long after adding .png: %s\n", requested_path);
                Send404Response(client_socket, not_found_page);
                isprocessingrequest = 0;
                return;
            }
            
            status_filepath[i] = 0;
            
            // Security: Validate the constructed file path
            if (!IsSecurePath(status_filepath)) {
                printf("SECURITY: Blocked unsafe status path attempt: %s\n", status_filepath);
                Send404Response(client_socket, not_found_page);
                isprocessingrequest = 0;
                return;
            }
            
            I64 result = SendFile(client_socket, status_filepath, "image/png", 200);
            if (result < 0) {
                printf("Status file '%s' not found, sending 404\n", status_filepath);
                Send404Response(client_socket, not_found_page);
            } else {
                printf("Status file '%s' sent successfully!\n", status_filepath);
            }
        } else {
            printf("Path '%s' not found - sending 404\n", requested_path);
            Send404Response(client_socket, not_found_page);
        }
    } else {
        printf("Unsupported HTTP method: %s - sending 404\n", http_method);
        Send404Response(client_socket, not_found_page);
    }

    isprocessingrequest = 0;
}


// main sever
// ===========================================================

U0 main() {
    I64 server_socket, client_socket;
    U8 client_address[16];
    I64 address_length = 16;
    
    // Initialize rate limiting
    isprocessingrequest = 0;
    
    printf("\n");
    printf("========================================\n");
    printf("Holy C Web Server\n");
    printf("========================================\n");
    printf("Starting server .\n");
    
    // create and configure the server socket
    server_socket = CreateServerSocket(SERVER_PORT);
    if (server_socket < 0) {
        printf("ERROR: Failed to create server socket!\n");
        printf("   Make sure port %lld is available.\n", SERVER_PORT);
        return;
    }
    
    printf("\nSTARTED!\n");
    printf("Listening on port %lld\n", SERVER_PORT);
    printf("Access at: http://localhost:%lld/\n", SERVER_PORT);
    printf("Press Ctrl+C to stop the server\n");
    printf("=======================================\n\n");
    
    // server loop
    while (1) {
        printf("Waiting for incoming connections...\n");
        
        client_socket = Accept(server_socket, client_address, &address_length);
        
        if (client_socket < 0) {
            printf("WARNING: Failed to accept connection (error %lld)\n", client_socket);
            printf("Continuing to wait for next connection...\n\n");
            continue;
        }
        
        if (isprocessingrequest) {
            printf("RATE LIMIT: Already processing a request, sending 503\n");
            Send503Response(client_socket, rate_limit_page);
            Close(client_socket);
            printf("Rate limited client disconnected\n");
            printf("----------------------------------------\n\n");
            continue;
        }
        
        ProcessClientRequest(client_socket);
        
        printf("Closing client connection...\n");
        Close(client_socket);
        printf("Client disconnected\n");
        printf("----------------------------------------\n\n");
    }
    
    // if you somehow get here welldone 
    printf("Shutting down server...\n");
    Close(server_socket);
    printf("Server stopped. Goodbye!\n");
}
