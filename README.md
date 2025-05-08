# GPU VRAM & Utilization PowerShell Script for Windows

This repository contains `gpu_ulil.ps1`, a PowerShell script designed to retrieve dedicated GPU VRAM (Used/Total) and GPU utilization percentage on Windows systems.

It primarily sources VRAM information from the Windows Registry (for the non-NVIDIA GPU with the most reported VRAM) and utilization/used VRAM from Performance Counters.

## Features

*   Outputs a simple semicolon-separated string for easy parsing by other applications:
    `USED_VRAM_GB;TOTAL_VRAM_GB;UTILIZATION_PERCENT`
    (e.g., `1.5;8.0;65` or `N/A` for unavailable data)
*   Optional formatted table output for direct human-readable diagnostics.
*   Verbose output mode for troubleshooting.

## Standalone Usage

1.  **Download `gpu_ulil.ps1`**.
2.  **Open PowerShell.**
3.  **Navigate to the script's directory.**
4.  **Run the script:**

    *   **For application-compatible output (semicolon-separated):**
        ```powershell
        .\gpu_ulil.ps1
        ```

    *   **For a human-readable formatted table:**
        ```powershell
        .\gpu_ulil.ps1 -FormatTable
        ```
        This will also include the semicolon-separated string first.

    *   **Allow script execution (if needed):**
        If you encounter execution policy issues, you might need to run it like this:
        ```powershell
        powershell.exe -ExecutionPolicy Bypass -File .\gpu_ulil.ps1
        ```
        (Add `-FormatTable` as needed after the script name).

## Integration with Other Applications

This script is designed to be embeddable. Applications can:
1.  Include the script's content.
2.  Execute it via `powershell.exe -Command "<script_content>"`.
3.  Parse the first line of `stdout` (the semicolon-separated values).

This script provides a fallback mechanism for GPU monitoring on Windows when tools like `nvidia-smi` are not available or applicable.
