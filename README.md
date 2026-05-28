# rbx-algorithms
Collection of various algorithms for Luau, optimized for speed

# Installation

### Wally

```toml
[dependencies]
algorithms = "daily3014/algorithms@0.1.0"
```

### Pesde

```sh
pesde add daily3014/algorithms
```

# Algorithms
Checksums: CRC32, Adler32\
Encoding: Base64, Hexadecimal, JSON, MessagePack\
Pathfinding: A*

# Benchmarks
## Checksums
### Adler32
| Provider          | Speed      | Relative Speedup  | Pure Luau? |
|-------------------|------------|-------------------|------------|
| **rbx-algorithm** | 1.23 GB/s  | -                 | Yes        |
### CRC32
| Provider          | Speed       | Relative Speedup  | Pure Luau? |
|-------------------|-------------|-------------------|------------|
| **rbx-algorithm** | 139.6 MB/s  | -                 | Yes        |
## Encoding
### Base64
| Provider      | Speed     | Relative Speedup  | Pure Luau? |
|---------------|-----------|-------------------|------------|
| Reselim       | 165 MB/s  | -                 | Yes        |
| Lute          | 219 MB/s  | 1.32x faster      | Yes        |
| rbx-algorithm | 664 MB/s  | 4.02x faster      | Yes        |
| **Roblox**    | 1781 MB/s | 10.79x faster     | No         |
### Hexadecimal
### JSON
| Provider          | Decoding | Encoding | Relative Speedup       | Pure Luau? |
|-------------------|----------|----------|------------------------|------------|
| rxi/json.lua      | 35 MB/s  | 35 MB/s  | -                      | Yes (Lua)  |
| grafi-tt/lunajson | 121 MB/s | 81 MB/s  | 3.46x / 2.31x faster   | Yes (Lua)  |
| Roblox            | 513 MB/s | 317 MB/s | 14.66x / 9.06x faster  | No         |
| **rbx-algorithm** | 772 MB/s | 932 MB/s | 22.06x / 26.63x faster | Yes        |
### MessagePack
## Pathfinding
### A*