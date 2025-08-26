package main

import (
    "bytes"
    "context"
    "encoding/json"
    "fmt"
    "io"
    "log"
    "mime/multipart"
    "net/http"
    "os"
    "path/filepath"
    "strings"
    "sync"
    "time"

    "golang.org/x/time/rate"
)

var (
    folderPath        = os.Getenv("TORBOX_WATCH_FOLDER")
    torboxAPIKey      = os.Getenv("TORBOX_API_KEY")
    deleteAfterUpload bool
    httpClient        *http.Client
    limiter           *rate.Limiter
    failedUploads     = make(map[string]time.Time)
    failedUploadsMux  sync.Mutex
    processedFiles    = make(map[string]time.Time)
    processedFilesMux sync.Mutex
    scanInterval      = 20 * time.Second
    retryInterval     = 15 * time.Minute
    pausedUntil       time.Time
    pauseMux          sync.Mutex
)

const (
    maxRetries       = 3
    baseDelay        = 1 * time.Second
    torboxAPIBase    = "https://api.torbox.app"
    torboxAPIVersion = "v1"
    maxWorkers       = 5
    fileExpiry       = 24 * time.Hour
)

type TorBoxResponse struct {
    Success bool   `json:"success"`
    Detail  string `json:"detail"`
}

func init() {
    deleteAfterUpload = strings.ToLower(os.Getenv("DELETE_AFTER_UPLOAD")) == "true"
    httpClient = &http.Client{
        Timeout: 30 * time.Second,
        Transport: &http.Transport{
            MaxIdleConns:        100,
            MaxIdleConnsPerHost: 100,
            IdleConnTimeout:     90 * time.Second,
        },
    }
    limiter = rate.NewLimiter(rate.Every(time.Second), 10)
}

// --- pause handling ---
func checkPause(ctx context.Context) {
    pauseMux.Lock()
    until := pausedUntil
    pauseMux.Unlock()

    if until.After(time.Now()) {
        wait := time.Until(until)
        log.Printf("⏸ Paused for %s due to previous error", wait)
        select {
        case <-time.After(wait):
            return
        case <-ctx.Done():
            return
        }
    }
}

func triggerPause() {
    pauseMux.Lock()
    pausedUntil = time.Now().Add(5 * time.Minute)
    pauseMux.Unlock()
    log.Printf("⚠️ Error detected, pausing ALL uploads for 5 minutes")
}

// --- file moving for nzb ---
func moveToUploaded(filename string) {
    uploadedDir := filepath.Join(folderPath, "uploaded")
    log.Printf("Moving NZB into uploaded/: %s", filename)

    if err := os.MkdirAll(uploadedDir, 0755); err != nil {
        log.Printf("Warning: failed to create uploaded folder: %v", err)
        return
    }

    newPath := filepath.Join(uploadedDir, filepath.Base(filename))
    if err := os.Rename(filename, newPath); err != nil {
        log.Printf("Warning: failed to move %s: %v", filename, err)
    } else {
        log.Printf("✅ Moved NZB -> %s", newPath)
    }
}

// --- upload functions ---
func uploadToTorBox(ctx context.Context, filename string) error {
    log.Printf("Processing: %s", filename)

    if strings.HasSuffix(filename, ".magnet") {
        magnetLink, err := os.ReadFile(filename)
        if err != nil {
            return fmt.Errorf("read magnet file: %w", err)
        }
        err = tryUploadMagnet(ctx, string(magnetLink))
        if err == nil {
            log.Printf("✅ Uploaded magnet: %s", filename)
            if deleteAfterUpload {
                os.Remove(filename)
            }
        } else {
            failedUploadsMux.Lock()
            failedUploads[filename] = time.Now()
            failedUploadsMux.Unlock()
        }
        return err
    }

    file, err := os.Open(filename)
    if err != nil {
        return fmt.Errorf("open file: %w", err)
    }
    defer file.Close()

    var uploadErr error
    if strings.HasSuffix(filename, ".nzb") {
        uploadErr = tryUploadUsenet(ctx, file, filename)
    } else {
        uploadErr = tryUploadTorrent(ctx, file, filename)
    }

    if uploadErr == nil {
        log.Printf("✅ Uploaded: %s", filename)
        if strings.HasSuffix(filename, ".nzb") {
            moveToUploaded(filename)
        } else if deleteAfterUpload {
            os.Remove(filename)
        }
        return nil
    }

    failedUploadsMux.Lock()
    failedUploads[filename] = time.Now()
    failedUploadsMux.Unlock()
    return uploadErr
}

func tryUploadMagnet(ctx context.Context, magnetLink string) error {
    url := fmt.Sprintf("%s/%s/api/torrents/createtorrent", torboxAPIBase, torboxAPIVersion)
    formData := map[string]string{"magnet": strings.TrimSpace(magnetLink), "seed": "1", "allow_zip": "true"}
    body := &bytes.Buffer{}
    writer := multipart.NewWriter(body)
    for k, v := range formData {
        writer.WriteField(k, v)
    }
    writer.Close()
    req, _ := http.NewRequestWithContext(ctx, "POST", url, body)
    req.Header.Set("Content-Type", writer.FormDataContentType())
    req.Header.Set("Authorization", "Bearer "+torboxAPIKey)

    resp, err := httpClient.Do(req)
    if err != nil {
        return err
    }
    defer resp.Body.Close()
    if resp.StatusCode != http.StatusOK {
        return fmt.Errorf("bad status: %d", resp.StatusCode)
    }
    var r TorBoxResponse
    json.NewDecoder(resp.Body).Decode(&r)
    if !r.Success {
        return fmt.Errorf("API error: %s", r.Detail)
    }
    return nil
}

func streamMultipartUpload(ctx context.Context, url, fileHeader string, file *os.File, extra map[string]string) error {
    pr, pw := io.Pipe()
    writer := multipart.NewWriter(pw)
    go func() {
        defer pw.Close()
        defer writer.Close()
        part, _ := writer.CreateFormFile("file", fileHeader)
        io.Copy(part, file)
        for k, v := range extra {
            writer.WriteField(k, v)
        }
    }()
    req, _ := http.NewRequestWithContext(ctx, "POST", url, pr)
    req.Header.Set("Content-Type", writer.FormDataContentType())
    req.Header.Set("Authorization", "Bearer "+torboxAPIKey)
    resp, err := httpClient.Do(req)
    if err != nil {
        return err
    }
    defer resp.Body.Close()
    if resp.StatusCode != http.StatusOK {
        return fmt.Errorf("bad status: %d", resp.StatusCode)
    }
    var r TorBoxResponse
    json.NewDecoder(resp.Body).Decode(&r)
    if !r.Success {
        return fmt.Errorf("API error: %s", r.Detail)
    }
    return nil
}

func tryUploadTorrent(ctx context.Context, file *os.File, filename string) error {
    url := fmt.Sprintf("%s/%s/api/torrents/createtorrent", torboxAPIBase, torboxAPIVersion)
    return streamMultipartUpload(ctx, url, filepath.Base(filename), file, map[string]string{"seed": "1", "allow_zip": "true"})
}

func tryUploadUsenet(ctx context.Context, file *os.File, filename string) error {
    url := fmt.Sprintf("%s/%s/api/usenet/createusenetdownload", torboxAPIBase, torboxAPIVersion)
    name := strings.TrimSuffix(filepath.Base(filename), ".nzb")
    return streamMultipartUpload(ctx, url, filepath.Base(filename), file, map[string]string{"name": name, "password": "vietnzb.club"})
}

// --- scanning and worker loop ---
func shouldProcessFile(filename string) bool {
    return strings.HasSuffix(filename, ".torrent") ||
        strings.HasSuffix(filename, ".magnet") ||
        strings.HasSuffix(filename, ".nzb")
}

func scanDirectory(ctx context.Context, uploadChan chan<- string) {
    entries, _ := os.ReadDir(folderPath)
    for _, entry := range entries {
        if entry.IsDir() {
            continue
        }
        fullPath := filepath.Join(folderPath, entry.Name())
        if shouldProcessFile(fullPath) {
            uploadChan <- fullPath
        }
    }
}

func watchFolder(ctx context.Context) {
    uploadChan := make(chan string, 100)
    var wg sync.WaitGroup

    for i := 0; i < maxWorkers; i++ {
        wg.Add(1)
        go func(id int) {
            defer wg.Done()
            for filename := range uploadChan {
                checkPause(ctx) // <-- check before each upload
                if err := uploadToTorBox(ctx, filename); err != nil {
                    log.Printf("Worker %d: upload error %s: %v", id, filename, err)
                    triggerPause() // <-- pause everyone
                }
            }
        }(i)
    }

    ticker := time.NewTicker(scanInterval)
    defer ticker.Stop()

    for {
        select {
        case <-ctx.Done():
            close(uploadChan)
            wg.Wait()
            return
        case <-ticker.C:
            scanDirectory(ctx, uploadChan)
        }
    }
}

func main() {
    if folderPath == "" || torboxAPIKey == "" {
        log.Fatal("Please set TORBOX_WATCH_FOLDER and TORBOX_API_KEY")
    }
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()
    log.Printf("🚀 Starting TorBox uploader (watching %s)", folderPath)
    watchFolder(ctx)
}
