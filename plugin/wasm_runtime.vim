" wasm_runtime
" Author: skanehira
" License: MIT

if exists('loaded_wasm_runtime')
  finish
endif
let g:loaded_wasm_runtime = 1

command! -nargs=+ -complete=file WasmRuntimeRun call wasm_runtime#run(<f-args>)
