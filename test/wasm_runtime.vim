let s:suite = themis#suite('wasm_runtime')
let s:assert = themis#helper('assert')

function s:suite.fib()
  let runtime = wasm_runtime#new('./test/test.wasm')
  let tests = [
        \ [1, 1],
        \ [2, 1],
        \ [3, 2],
        \ [4, 3],
        \ [5, 5],
        \ [6, 8],
        \ [7, 13],
        \ [8, 21],
        \ ]
  for test in tests
    let result = runtime.invoke('fib', test[0])
    call s:assert.equals(result, test[1])
  endfor
endfunction
