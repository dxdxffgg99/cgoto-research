# 선행 연구 목록

인터프리터 디스패치(switch / computed goto / tail call)와 분기 예측에 관한 자료 모음.
각 항목은 **무엇을 주장했나**, **우리 연구와의 관계** 순서로 정리했다.
⚠️ 표시는 2차 자료(메일링 리스트, 요약 글)에서 가져온 내용이라 원문 확인이 필요한 부분이다.

## 추천 읽기 순서

1. Rohou, Swamy, Seznec (CGO 2015) — 우리가 다시 검증하는 대상
2. Ertl & Gregg (JILP 2003) — 2015 논문이 반박한 "통념"의 출처
3. Elhage (2025) + Ken Jin (2025) — 지금 시점의 computed goto vs tail call 논쟁
4. Haberman (2021) — musttail 디스패치의 실전 사례
5. 나머지는 필요할 때

---

## 1. 핵심 논문

### Rohou, Swamy, Seznec — Branch Prediction and the Performance of Interpreters: Don't Trust Folklore (CGO 2015)

- 링크: [HAL hal-01100647](https://hal.inria.fr/hal-01100647/document) · [PDF (core.ac.uk)](https://core.ac.uk/download/46812085.pdf) · [서지 (researchr)](https://researchr.org/publication/RohouSS15)
- 서지: CGO 2015, pp. 103–114, DOI 10.1109/CGO.2015.7054191
- 주장: "switch 디스패치는 간접 분기 예측이 잘 안 돼서 느리다"는 통념은 최신 x86에서 더 이상 맞지 않는다. Python, JavaScript, CLI 인터프리터를 Nehalem, Sandy Bridge, Haswell에서 측정했고, TAGE/ITTAGE 예측기로 시뮬레이션도 했다.
- ⚠️ python-dev 요약에 따르면 computed goto를 끈 Python 3.3의 평균 MPKI가 Nehalem 12.8 → Sandy Bridge 3.5 → Haswell 1.4로 줄었다. 같은 글은 이 논문이 computed goto 빌드와는 직접 비교하지 않았다고 지적한다. ([python-dev 스레드](https://mail.python.org/pipermail/python-dev/2015-August/141172.html), [후속 글](https://www.python.org/pipermail/python-dev/2015-August/141183.html))
- 반론: 초록이 결론을 과장했고, 큰 벤치마크에서는 간접 분기 예측 정확도가 여전히 중요하다는 주장. ([comp.compilers 22-10-056](https://compilers.iecc.com/comparch/article/22-10-056), [22-10-062](https://compilers.iecc.com/comparch/article/22-10-062))
- **우리와의 관계**: 출발점. 우리 데이터에서도 switch와 cgoto의 예측 실패 횟수는 거의 같다(i9 gcc `-O2` 기준 −4%). 이 논문의 결론과 맞는다. 우리 기여는 "그래도 cgoto가 빠르고, 그 이유는 예측이 아니라 디스패치 명령어 수"라는 점이다. 이 논문이 computed goto와 직접 비교하지 않았다면, 그 빈자리를 우리가 채우는 셈이다. → 원문에서 꼭 확인할 것.

### Ertl & Gregg — The Structure and Performance of Efficient Interpreters (JILP 2003)

- 링크: [PDF (jilp.org)](https://jilp.org/vol5/v5paper12.pdf) · [서지](https://corais.scss.tcd.ie/content/pages/publications/the-structure-and-performance-of-efficient-interpreters.html)
- 서지: Journal of Instruction-Level Parallelism vol. 5, 2003. 짧은 버전은 Euro-Par 2001.
- 주장: 효율적인 인터프리터는 간접 분기를 매우 많이 실행하고(전체 명령어의 3.2%~13%), 그래서 성능이 간접 분기 예측 정확도에 크게 좌우된다. 당시 예측기(BTB)에서는 switch보다 threaded code가 예측에 유리했다.
- **우리와의 관계**: Rohou 2015가 반박한 "통념"의 대표 출처. 서론에서 "2003년엔 이랬고, 2015년엔 이렇게 바뀌었고, 2026년엔?" 구도로 쓰기 좋다.

### Ertl & Gregg — Optimizing Indirect Branch Prediction Accuracy in Virtual Machine Interpreters (PLDI 2003 / TOPLAS 2007)

- 링크: [PDF (TOPLAS판, Maynooth)](https://mural.maynoothuniversity.ie/id/eprint/10188/1/KC-Optimizing-2007.pdf) · [MURAL 레코드](https://mural.maynoothuniversity.ie/10188)
- 서지: PLDI 2003(Ertl & Gregg) / ACM TOPLAS 29(6), Article 37, 2007, DOI 10.1145/1286821.1286828. TOPLAS판 저자는 **Kevin Casey, M. Anton Ertl, David Gregg**(2026-11-23 확인: [MURAL](https://mural.maynoothuniversity.ie/10188), [Crossref](https://api.crossref.org/works/10.1145%2F1286821.1286828)). 초록: BTB 예측 정확도 2%~50%, 명령어 복제와 superinstruction으로 개선, Java와 Forth VM에 구현.
- 주장: 인터프리터는 실행 시간의 절반 이상을 간접 분기 예측 실패에 쓸 수 있고, BTB의 예측 정확도는 2%~50%에 그친다. 명령어 복제(replication)와 superinstruction으로 예측 실패를 거의 없앨 수 있고, threaded code 대비 최대 4.55배 빨라졌다.
- **우리와의 관계**: "핸들러마다 간접 점프를 따로 두면 예측이 좋아진다"는 cgoto의 원래 근거. 우리 측정에서 clang이 switch의 간접 점프를 핸들러 10곳에 복제한 것은 이 아이디어를 컴파일러가 자동으로 하는 것으로 볼 수 있다.

## 2. 지금 시점의 논쟁: computed goto vs tail call (CPython)

### Nelson Elhage — Performance of the Python 3.14 tail-call interpreter (2025)

- 링크: [블로그](https://blog.nelhage.com/post/cpython-tail-call/) · 관련 보도 [LWN 1010905](https://lwn.net/Articles/1010905), [LWN 1013650](https://lwn.net/Articles/1013650/)
- 주장: CPython 3.14의 tail-call 인터프리터가 처음 보고된 만큼(10~15%) 빠른 건 아니었다. 비교 대상인 computed goto 빌드가 clang 19의 회귀 때문에 느려져 있었다. clang 19가 디스패치 간접 점프를 핸들러마다 복제(tail duplication)하던 것을 멈춰서 computed goto의 이점이 사라진 것. `-mllvm` 옵션으로 복구하면 차이가 ⚠️ 약 1~5%로 줄었다.
- **우리와의 관계**: 매우 중요. ① computed goto의 이점이 "간접 점프 복제"에 달려 있다는 실증 사례이고, ② 컴파일러 버전에 따라 결과가 크게 흔들린다는 증거다. 우리 clang 23은 switch에서도 점프를 복제하고 있으므로, 논문에서 컴파일러 버전과 생성 코드(간접 점프 개수)를 반드시 같이 보고해야 한다.

### Ken Jin — CPython tail-calling interpreter 관련 글 (2025)

- 링크: [블로그 "no longer sorry"](https://fidget-spinner.github.io/posts/no-longer-sorry.html) · [Python Discourse 제안 스레드](https://discuss.python.org/t/a-new-tail-calling-interpreter-for-significantly-better-interpreter-performance/76315) · [cpython#128563](https://github.com/python/cpython/issues/128563) · [cpython#130961](https://github.com/python/cpython/issues/130961)
- 주장: 고친 clang 기준으로 tail-call 인터프리터는 computed goto보다 ⚠️ pyperformance 기하평균 약 5% 빠르다(소폭 개선). MSVC는 computed goto가 없어서 switch를 쓰는데, Windows x86-64에서 tail call로 바꾸면 switch 대비 ⚠️ 15~20% 빨라졌다.
- **우리와의 관계**: 실제 대형 인터프리터에서의 수치라서 우리 마이크로벤치마크와 비교하기 좋다. "switch 대비 15~20%"는 우리 결과(17~26%)와 크기가 비슷하다.

## 3. 디스패치 기법의 계보

### Bell — Threaded Code (CACM 1973)

- 링크: [CACM](https://cacmb4.acm.org/magazines/1973/6/11872-threaded-code) · DOI 10.1145/362248.362270
- 서지: Communications of the ACM 16(6):370–372, 1973
- 주장: "threaded code"라는 용어를 처음 널리 쓴 논문. 기계어 대신 루틴 주소의 나열로 프로그램을 표현한다.
- **우리와의 관계**: 배경 소개용 인용. cgoto(direct threading)의 원조.

### Piumarta & Riccardi — Optimizing Direct Threaded Code by Selective Inlining (PLDI 1998)

- 링크: [서지](https://bibtex.github.io/PLDI-1998-PiumartaR.html)
- 서지: PLDI 1998, pp. 291–300. DOI 10.1145/277650.277743(BibSonomy 기준, 2026-11-23). 277652.277743로 적은 자료도 있으나 PLDI '98 프로시딩 접두어는 277650 → 277650 쪽을 쓴다(ACM DL에서 최종 확인).
- 주장: 자주 나오는 명령어 열의 핸들러를 실행 시간에 이어 붙여(inlining) 기본 블록 안의 디스패치를 없앤다.
- **우리와의 관계**: "디스패치 비용 자체를 줄이는" 방향의 고전. 우리 주장(이득은 디스패치 명령어 수에서 온다)과 같은 방향.

### Berndl, Vitale, Zaleski, Brown — Context Threading (CGO 2005)

- 링크: [서지](https://bibtex.github.io/CGO-2005-BerndlVZB.html) · [발표 슬라이드](https://cdp-workshop.github.io/CDP/previous/CDP05/slides/CDP05-berndl.pdf) · [Zaleski 박사논문](https://www.eecg.utoronto.ca/~stumm/Theses/Zaleski-PhD08.pdf)
- 서지: CGO 2005, pp. 15–26
- 주장: 간접 점프 대신 네이티브 call/return을 써서 가상 PC와 실제 분기 대상의 관계를 하드웨어가 볼 수 있게 한다. ⚠️ 분기 예측 실패의 95%를 없애고 실행 시간을 30~40% 줄였다(슬라이드 기준).
- **우리와의 관계**: 예측 실패를 줄이려는 2000년대 연구의 대표. 2015년 이후 예측기가 좋아지면서 이런 기법의 동기가 약해졌는지가 논점이 될 수 있다.

### Shi, Gregg, Beatty, Ertl — Virtual Machine Showdown: Stack versus Registers (VEE 2005 / TACO 2008)

- 링크: [VEE 2005 PDF](https://usenix.org/legacy/events/vee05/full_papers/p153-yunhe.pdf) · [TACO 2008 PDF](https://mural.maynoothuniversity.ie/10185/1/KC-Virtual-2008.pdf)
- 서지: VEE 2005 / ACM TACO 4(4):21, 2008, DOI 10.1145/1328195.1328197
- 주장: 레지스터 VM이 스택 VM보다 디스패치 횟수가 적어서 빠르다. AMD64에서 switch 디스패치 기준 1.48배, inline threading 기준 1.15배.
- **우리와의 관계**: "디스패치 횟수와 명령어 수가 성능을 좌우한다"는 주장의 근거. 디스패치 방식에 따라 이득 폭이 달라진다는 점도 우리 결과와 연결된다.

## 4. 하드웨어 분기 예측기

### Seznec — A 64-Kbytes ITTAGE Indirect Branch Predictor (2011)

- 링크: [HAL hal-00639041](https://hal.archives-ouvertes.fr/hal-00639041v1) · [PDF (core.ac.uk)](https://core.ac.uk/download/163003428.pdf)
- 주장: TAGE의 간접 분기 버전. 여러 길이의 분기 이력으로 인덱싱한 태그 테이블로 간접 점프의 대상을 예측한다. 분기 예측 챔피언십 출품작.
- **우리와의 관계**: Rohou 2015가 "최신 예측기는 switch도 잘 맞힌다"고 할 때 근거로 든 예측기. 인텔 Haswell 이후 예측기가 이 계열이라고 흔히 말하지만, 인텔이 공식 확인한 것은 아니므로 논문에서는 조심해서 써야 한다.

## 5. musttail / tail-call 디스패치

### Josh Haberman — Parsing Protobuf at 2+GB/s: How I Learned To Love Tail Calls in C (2021)

- 링크: [원문 사본](https://engineered.at/articles/parsing-protobuf-at-2-gb-s-how-i-learned-to-love-tail-calls-in-c) · [upb dispatch.h](https://flutter.googlesource.com/third_party/protobuf/+/07e072aa79c893129f51f0fd5d33d6cccf33b446/upb/wire/decode_fast/dispatch.h)
- 주장: 파서를 연산 단위의 작은 함수로 나누고 `[[clang::musttail]]`로 다음 함수를 호출하면, 컴파일러가 각 함수의 레지스터 할당을 잘 해서 2GB/s 이상이 나온다. 단, "tail call = 2배"로 받아들이면 안 된다고 본인이 강조한다.
- **우리와의 관계**: 우리 `musttail_args` 변형(상태를 인자로 넘겨 레지스터에 고정)과 같은 설계. 우리 결과에서 clang은 이 방식으로 cgoto 수준까지 갔고 gcc는 아니었다.

### GCC 15 — musttail 지원

- 링크: [GCC 15 changes](https://gcc.gnu.org/gcc-15/changes.html) · [GCC 15.1 발표](https://gcc.gnu.org/pipermail/gcc-announce/2025/000185.html) · [PR83324](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=83324)
- 내용: GCC 15(2025년 4월)부터 `musttail` 속성 지원. clang 표기도 받는다. 최적화를 끈 상태에서도 테일 호출로 바꾼다.
- **우리와의 관계**: gcc와 clang에서 musttail을 같은 조건으로 비교할 수 있게 된 건 최근이다. 우리 비교가 의미 있는 이유 중 하나. 우리 `-O0` 빌드에서도 musttail이 정상 동작한 것과 맞는다.

### wasm3 — tail-call 기반 WebAssembly 인터프리터

- 링크: [wasm3 GitHub](https://github.com/wasm3/wasm3) · [tail call 관련 이슈 #74](https://github.com/wasm3/wasm3/issues/74)
- 내용: 바이트코드를 "operation" 함수 열로 바꾸고 tail call로 이어 실행한다. VM 레지스터를 함수 인자로 넘겨 실제 CPU 레지스터에 올린다. 일부 임베디드 타깃(ESP32 등)은 ABI 제약으로 tail call이 안 된다.
- **우리와의 관계**: 실사용 인터프리터 중 tail-call 디스패치 사례. 이식성 한계의 예시로도 쓸 수 있다.

### Ben L. Titzer — A Fast In-Place Interpreter for WebAssembly (OOPSLA 2022)

- 링크: [arXiv 2205.01183](https://arxiv.org/pdf/2205.01183)
- 주장: Wasm 바이트코드를 변환 없이 그대로 해석하는 in-place 인터프리터 설계. 비교 실험에서 ⚠️ wasm3가 가장 빨랐고 WAMR fast 인터프리터가 1.5~1.7배 느린 2위였다.
- **우리와의 관계**: Wasm 인터프리터를 실험 대상으로 고를 때의 기준 자료. wasm3(tail call), WAMR(label table) 등 디스패치 방식이 다른 실제 구현들의 성능 비교가 있다.

### Haoran Xu & Fredrik Kjolstad — Deegen: A JIT-Capable VM Generator for Dynamic Languages (2024)

- 링크: [arXiv 2411.11469](https://arxiv.org/abs/2411.11469) · [LLVM Dev Meeting 2023 슬라이드](https://www.llvm.org/devmtg/2023-10/slides/techtalks/Xu-Deegen-LLVM-Based-Compiler.pdf) · [저자 블로그](https://sillycross.github.io)
- 주장: 바이트코드 의미를 C++로 쓰면 인터프리터와 베이스라인 JIT를 자동 생성한다. 생성된 Lua 인터프리터(LuaJIT Remake)는 LuaJIT의 손으로 짠 어셈블리 인터프리터보다 평균 31% 빠르다.
- **우리와의 관계**: tail-call 스타일 디스패치를 컴파일러 도구로 극한까지 밀어붙인 최신 사례. 관련 연구 절에서 "생성형 접근"으로 소개.

### Rust — explicit tail calls (`become`)

- 링크: [RFC 3407 PR](https://github.com/rust-lang/rfcs/pull/3407) · [unstable book](https://doc.rust-lang.org/unstable-book/language-features/explicit-tail-calls.html)
- 내용: Rust에도 보장된 tail call(`become`)이 실험 기능으로 들어오는 중. 아직 미완성.
- **우리와의 관계**: musttail 방식이 C 밖으로도 퍼지는 흐름. 논의 절에서 한 줄 정도.

## 6. 실무자 관점 (논문 인용보다는 배경 이해용)

- **Mike Pall (LuaJIT), lua-l 2011**: C로 짠 switch 인터프리터는 컴파일러가 핵심 변수를 레지스터에 유지하기 어렵고, computed goto도 근본 해결은 아니라서 LuaJIT 인터프리터는 어셈블리로 짰다는 설명. [lua-l 2011-02/msg00742](https://lua-users.org/lists/lua-l/2011-02/msg00742.html) · [msg00751](https://lua-users.org/lists/lua-l/2011-02/msg00751.html) · [HN 토론](https://news.ycombinator.com/item?id=4852357)
- **Matt Keeter, Beating the compiler (2024)**: 인터프리터 루프를 어셈블리로 짜서 컴파일러를 이긴 실험기. [블로그](https://www.mattkeeter.com/blog/2024-07-12-interpreter/)
- **Python on WebAssembly 디스패치 논의**: gcc에서는 tail call이 computed goto보다 8% 느렸고 clang에서는 1% 빨랐다는 등, 컴파일러에 따라 결과가 뒤집힌 사례. [Python Discourse](https://discuss.python.org/t/interpreter-dispatch-and-performance-on-webassembly/27246)

## 7. 측정 방법론

### Mytkowicz, Diwan, Hauswirth, Sweeney — Producing Wrong Data Without Doing Anything Obviously Wrong! (ASPLOS 2009)

- 주장: 링크 순서나 환경 변수 크기처럼 겉보기에 상관없는 요인만 바꿔도 코드와 스택의 배치가 달라져, 성능이 크게 흔들리고 결론이 뒤집힐 수 있다(measurement bias). 배치를 무작위로 바꿔 가며 여러 번 재는 방식을 권한다.
- 서지(2026-11-23 확인): ASPLOS XIV, Washington DC, 2009년 3월, pp. 265–276, DOI 10.1145/1508244.1508275. ([USI 목록](https://sape.inf.usi.ch/publications/asplos09), [Unpaywall](https://unpaywall.org/10.1145%2F1508244.1508275)) BibSonomy의 1508284.1508275는 SIGPLAN Notices 쪽 접두어와 섞인 오기로 보인다.
- **우리와의 관계**: clang `-O3` musttail의 분기 예측 실패 급증(마이크로벤치마크, `-O2` 대비 1.8배)을 해석할 때 꼭 필요하다. `analysis/layout_sweep.sh`로 코드 위치를 바꿔 가며 재는 실험이 이 논문이 권하는 방법과 같은 취지다. 배치 우연으로 밝혀지면 "tail call 디스패치가 cgoto보다 배치에 민감하다"는 근거가 된다.

## 8. Rohou 2015를 인용한 이후 연구 (Semantic Scholar 인용 32건, 2026-11-23)

우리 주제와 직접 관련된 것만 추렸다.

### Zheng & Sasaki — Improving Indirect Branch Prediction in Interpreters via Hardware/Software Co-Design (IEEE CAL 2026)

- 링크: [arXiv 2609.34263](https://arxiv.org/abs/2609.34263) · DOI 10.1109/LCA.2026.3738406
- 주장: 소프트웨어가 넘겨주는 바이트코드 메타데이터로 다음 디스패치 대상을 미리 프런트엔드에 넣는 1.3KB 하드웨어 엔진. 16KB ITTAGE 대비 바이트코드 점프 MPKI −73.7%, IPC +3.2%(조화평균). CPython 3.13(PGO+LTO), gem5 AArch64 시뮬레이션. 동기 측정은 i7-13700H P코어.
- 디스패치 방식(switch/cgoto/tail call)은 비교하지 않는다. 기준선은 computed goto이고 "핸들러 끝마다 디스패치를 복제한다"고 전제한다.
- **우리와의 관계**: 최신 연구도 "인터프리터 = 간접 분기 예측 문제"라는 구도를 유지한다. 우리 결과(예측 실패는 사이클의 약 3%, 복제의 이득은 프런트엔드)와 대비되는 관점. 또 우리 5.3은 "cgoto라고 해서 복제가 보장되지 않는다"(Lua gcc 6개, clang 21 AArch64 1개)를 보여 주므로 이 논문의 전제를 보완한다.

### Ertl & Paysan — The Performance Effects of Virtual-Machine Instruction Pointer Updates (ECOOP 2024)

- 링크: [LIPIcs](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ECOOP.2024.14) · DOI 10.4230/LIPIcs.ECOOP.2024.14 · LIPIcs 313, 14:1–14:26
- 주장: 가상 IP 갱신의 의존 사슬이 최신 out-of-order 코어에서 임계 경로가 된다. 사슬을 줄이는 기법으로 일부 벤치마크가 2배 이상 빨라짐.
- **우리와의 관계**: "디스패치 비용은 예측이 아니라 다른 데(의존 사슬, 프런트엔드)에 있다"는 같은 계열의 최신 근거. top-down 분석(남은 일 2) 해석에 인용. ⚠️ 본문은 아직 안 읽음.

### 그 밖의 인용 논문 (제목 수준 확인)

- Interpretizer: A Compiler-Independent Conversion of Switch-Based Dispatch into Threaded Code (2019, ICSOFT 계열로 표기) — switch → threaded code 자동 변환. 우리 C2(변환 도구)와 가장 가까운 선행 작업. ⚠️ 저자·DOI 미확인.
- Short-Circuit Dispatch: Accelerating Virtual Machine Interpreters on Embedded Processors (ISCA 2016) — 하드웨어 디스패치 가속.
- Bungee jumps: Accelerating indirect branches through HW/SW co-design (MICRO 2015).
- RegCPython: A Register-based Python Interpreter for Better Performance (TACO 2022).
- An Attempt to Catch Up with JIT Compilers: The False Lead of Optimizing Inline Caches (Programming 2025).
- Titzer, A fast in-place interpreter for WebAssembly (OOPSLA 2022) — 이미 5절에 있음.
- → 2020년 이후에도 switch / computed goto / tail call을 실측으로 함께 비교한 학술 논문은 이 목록에 없다.

### Rohou 2015 원문 확인 상태

- 서지는 Semantic Scholar로 확인(DBLP conf/cgo/RohouSS15, DOI 10.1109/CGO.2015.7054191).
- ⚠️ 본문(HAL, core.ac.uk)은 자동 접근이 막혀 있어 읽지 못했다. "computed goto 빌드와 직접 비교하지 않았다"는 python-dev 요약의 지적은 원문 PDF를 직접 받아 확인해야 한다.

## 9. LLVM의 computed goto 꼬리 복제 이력

- clang은 함수 안의 computed goto를 `indirectbr` 하나로 모은 뒤, 코드 생성 단계의 꼬리 복제(TailDuplicator)로 다시 핸들러마다 펼친다(Elhage 2025).
- LLVM PR #114990(2024~2025): computed goto 블록을 더 적극적으로 복제. ([llvm-commits](https://lists.llvm.org/pipermail/llvm-commits/Week-of-Mon-20250120/1552174.html))
- LLVM PR #150911(Florian Hahn, 2025): 적극적 복제를 레지스터 할당 뒤로 미룸. 레지스터 할당 전에 복제하면 macOS의 Python 3.12에서 3% 손해가 났기 때문. 2025년 8월 릴리스 브랜치에 백포트. ([llvm-branch-commits](https://lists.llvm.org/pipermail/llvm-branch-commits/2025-August/069426.html))
- 우리 관찰과 맞는다: clang 23에서 Lua/CPython의 점프는 early tail duplication 뒤에는 1개이고, 레지스터 할당 뒤 tail duplication과 블록 배치에서 늘어난다(5.3).

## 10. 아직 못 찾은 것 (추가 조사 필요)

- **2020년 이후 AMD, ARM에서 switch / computed goto / tail call을 체계적으로 비교한 학술 논문.** 웹 검색으로는 블로그와 포럼 글만 나왔다. 검색이 완전하지 않으니 ACM DL과 Google Scholar에서 VMIL, MPLR, CGO, VEE, ECOOP 워크숍을 직접 찾아봐야 한다. 정말 없다면 우리 논문의 빈자리가 된다.
- **LLVM의 tail duplication이 indirectbr/switch에 적용되는 조건.** → 9절과 `results/analysis/compiler_versions.txt`(버전별 점프 수)로 일부 해결.
- **Ertl & Gregg의 dynamic superinstruction / replication 후속 연구.** Rohou 2015 인용 논문은 8절에 정리.
