# 논문 개요 (작업용)

상태 표시: ✅ 데이터 있음 · 🔄 측정/분석 중 · ⬜ 아직 안 함
수치는 2026-11-23 아침 기준이다(예약한 측정 전부 완료). 이후 재측정 시 바꿔 넣는다.

## 가제

- **It's the Compiler, Not the Predictor: Interpreter Dispatch a Decade after "Don't Trust Folklore"**
- 대안: *Dispatch Revisited: switch, computed goto and tail calls on modern CPUs and compilers*

## 한 문단 요약 (초록 초안)

Rohou 등(CGO 2015)은 최신 분기 예측기가 switch 디스패치의 간접 분기도 잘 맞힌다는 것을 보였다.
10년 뒤 우리는 switch, computed goto(cgoto), tail call(musttail, preserve_none) 디스패치를
마이크로벤치마크와 실제 인터프리터 3개(Lua 5.4, WAMR, CPython 3.15)에서 gcc 16과 clang 23,
최적화 단계 -O0~-O3, 두 세대의 인텔 CPU와 ARM 모바일 코어(Snapdragon 8 Elite의 Oryon)로
비교한다. 분기 예측 실패 횟수는 디스패치 방식과 거의 무관했다. 성능 차이를 만드는 것은
컴파일러였다. 간접 점프를 핸들러마다 복제하느냐, switch를 점프 테이블로 만드느냐 비교 트리로
만드느냐, preserve_none을 어떻게 구현하느냐, 최적화 단계가 어떻게 바뀌느냐에 따라 같은 디스패치
방식의 순위가 뒤집혔다. 인텔에서 1위였던 cgoto가 ARM에서는 tail call에 3~4% 뒤졌다. 또 코드 배치만 1바이트 바꿔도 간접 점프 예측이 무너져 45% 느려지는 사례를
찾았다. 이를 바탕으로 VM 구현자를 위한 판단 기준을 제시한다.

## 기여 (Contributions)

- **C1. 체계적 비교** — 디스패치 방식 × 컴파일러 × 최적화 단계 × CPU × 실제 인터프리터 3개. ✅ 대부분 / 🔄 일부
- **C2. 기존 인터프리터를 tail call 디스패치로 자동 변환하는 방법** — Lua(83개 핸들러), WAMR fast interpreter(6,300줄 함수 → 187개 함수). 핸들러 본문은 그대로, 제어 흐름만 변환. 공식 테스트와 프로그램 출력으로 검증. ✅
- **C3. 원인 분석** — 분기 예측이 아니라 컴파일러 코드 생성(점프 복제, 명령어 수, 호출 규약)이 차이를 만든다는 것을 카운터와 생성 코드로 보인다. 특히 computed goto의 핸들러별 디스패치가 컴파일러의 꼬리 병합에 의해 되돌려지며, 그 여부가 바이트코드 형식(고정 폭)과 컴파일 시간 한도(gcc 진입 간선 100개)라는 우연에 달려 있음을 보인다(5.3). ✅ (top-down i9·i5 포함. -O0: 의존 사슬 가설은 지연 주입으로 반박, 실행 병렬성 저하까지 확인, 근본 원인은 가설)
- **C4. 배치 민감도** — 코드 배치가 디스패치 성능을 크게 흔들 수 있음을 사례와 분포로 보인다. 100개 배치 × 두 CPU(섭동 도구 버그 수정 후 재측정)에서 간접 점프 예측 붕괴 확률은 **디스패치 방식으로는 갈리지 않고**(cgoto 1.5% 대 tail call 2.2%, p = 0.51) **컴파일러로 갈린다**(gcc 0.5% 대 clang 2.8%, p = 0.0003). 간접 점프가 하나뿐인 switch gcc만 구조상 0건. ARM(Oryon)에서는 간접 점프 붕괴가 0/404(x86 clang i5 16/404, i9 7/404). 대신 musttail clang에서만 9/101개 배치가 사이클 정확히 약 2배가 되는 다른 형태의 붕괴가 있다(프런트엔드 정체, 예측 실패로는 집계되지 않음). **Cortex-A76에서는 clang tail call만 붕괴하고(64/202, gcc는 0/404), 그 조건을 주소 규칙 하나로 정확히 설명하며 새 배치 200개에서 사전 예측이 200/200 맞았다(6.2d).** → 배치 위험은 방식의 성질이 아니라 (컴파일러가 낸 코드, CPU의 예측기) 조합의 결정적 성질. ✅ (2026-11-23 정정: 예전 "cgoto 0.7% 대 tail call 3.2%, p = 0.008"은 패딩이 실행된 배치가 섞인 결과)
- **C5. 실무 지침** — 언제 cgoto, 언제 tail call인가. ⬜ (결과가 다 나오면)

---

## 1. Introduction

- 인터프리터 디스패치의 "통념": switch는 분기 예측이 나빠서 느리다 → threaded code(cgoto)를 써라.
- Rohou 2015: 통념은 틀렸다(최신 예측기는 잘 맞힌다).
- 그 사이 바뀐 것: (1) clang 19 회귀로 CPython의 cgoto 이득이 사라진 사건(Elhage 2025), (2) musttail/preserve_none 기반 tail call 인터프리터의 등장(CPython 3.14, protobuf, wasm3), (3) GCC 15의 musttail 지원.
- 질문: 지금 디스패치 성능을 결정하는 것은 무엇인가? cgoto는 아직 쓸 가치가 있나?
- 답 요약 + 기여 목록.

## 2. Background

- 2.1 디스패치 기법: switch, cgoto(direct threading), tail call(handler-per-function + musttail).
- 2.2 분기 예측: 조건 분기 예측 vs 간접 분기 목적지 예측(BTB, ITTAGE 계열).
- 2.3 컴파일러가 하는 일: switch의 범위 검사, 간접 점프 꼬리 복제(tail duplication), PIE와 rip 상대 주소, preserve_none 호출 규약.
- 그림 후보: 세 방식의 디스패치 코드 비교(어셈블리 몇 줄씩).

## 3. Methodology

- 3.1 대상
  - 마이크로벤치마크: 콜라츠 계산 VM(명령어 7종). 변형 5개(switch, cgoto, musttail, musttail+no-pie, musttail+상태를 인자로). switch는 공정성을 위해 `case HALT` + `default: __builtin_unreachable()`. ✅
  - Lua 5.4.8 + AWFY 14개 벤치마크(커밋 f35aed0). 해시 시드 고정 + ASLR 끔. 변형: switch, cgoto, tail, tailpn. ✅
  - WAMR 2.4.6 fast interpreter + 저장소 내장 wasm 프로그램 8개(CoreMark 반복 고정 등). 변형: switch, cgoto, tail, tailpn. 🔄
  - CPython 3.15.2 + pyperformance 1.14.0(96개 + 세부 항목). 변형: switch, cgoto, tail(=preserve_none). PGO 없음 ✅ / PGO+LTO 🔄
- 3.2 환경: i5-1135G7(Tiger Lake), i9-14900K(Raptor Lake, P코어). gcc 16.2.1, clang 23.1.5. 터보 끔, 기본 클럭 고정.
  - 추가: 갤럭시 S25 Edge(SM-S937N, Snapdragon 8 Elite for Galaxy, Oryon 프라임 코어 cpu7, 안드로이드 16), Termux clang 21.1.8. 클럭 고정 불가(루팅 없음) → 사이클로만 비교.
  - OCI Ampere A1(Neoverse N1): 사용 불가로 제외(2026-11-22).
  - 추가(2026-11-23): **라즈베리 파이 5**(BCM2712, **Cortex-A76** 4코어, 최대 2.4GHz, 데비안 13, 커널 6.18). Cortex-A76은 Neoverse N1의 바탕 코어라 서버 ARM의 대용이 된다. 공용 장비(다른 사용자와 서비스 동작), 루트 없음 → 클럭 고정 불가(ondemand), perf 없음 → `bench/pstat`. 컴파일러는 홈에 설치: gcc 15.2.1(ARM GNU Toolchain 15.2.Rel1), clang 21.1.8(LLVM 공식 릴리스, 갤럭시와 같은 버전), 둘 다 공식 체크섬 확인. 측정 스크립트 `bench/pstat_all.sh`(빌드·검사를 끝낸 뒤 측정, 코어 3번 고정, 실행마다 50°C 이하로 식힘). 🔄 측정 중
    - gcc 15는 AArch64에서 `preserve_none`을 무시한다(`-Werror=attributes`로 확인) → tailpn은 clang만.
    - 간접 분기 예측 실패 이벤트: 탐침으로 **raw 0x118**(무작위 간접 7.01M, 무작위 조건 4, 예측 가능한 간접 26; `results/analysis/arm_pmu_scan_cortex-a76.txt`). Oryon의 0x8117과 번호는 다르지만 역할이 같다. 0x7a(BR_INDIRECT_SPEC)는 A76에서 실제 간접 분기 수와 거의 같다(Oryon은 잘못된 경로 실행으로 부풀었음).
- 3.2.1 기기별 측정 범위

  | 대상 | i5-1135G7 | i9-14900K | 갤럭시 (Oryon) | 파이 5 (Cortex-A76) |
  |---|---|---|---|---|
  | 마이크로벤치마크 | ✅ gcc+clang, -O0~-O3 | ✅ gcc+clang, -O0~-O3 | ✅ clang만, -O2/-O3, no-pie 제외 | ✅ gcc 15+clang 21, -O0~-O3, 5회 |
  | Lua + AWFY | ✅ -O2(재측정), ✅ -O3 | ✅ (시드 고정), ✅ -O3 | ✅ clang만, 3회 | ✅ -O2, 5회, tailpn은 clang만 |
  | WAMR | ✅ -O3, -O2 | ✅ -O3, -O2 | **제외** (결정 2026-11-22) | ✅ -O3, 5회, c-ray 장면 버전 추가 |
  | CPython | ⬜ | ✅ PGO 없음, ✅ PGO+LTO | 제외 | 제외(메모리 4GB, 빌드 시간) |
  | 배치 민감도 | ✅ 21개(10변형×2단계), ✅ 100개 | ✅ 100개 | ✅ 101개 × 4변형 | ✅ 101개 × 8변형 + 사전 예측 검증 200개 |

  - 갤럭시에서 WAMR 제외: 안드로이드용 빌드와 측정 경로(Termux 빌드 → adb shell 실행)를 따로 맞춰야 하는 데 비해 얻는 정보가 적다고 판단해 측정하지 않기로 함. CPython도 같은 이유로 제외.
- 3.2.2 안드로이드 측정에서 확인한 플랫폼 사실 (논문 재료)
  - 안드로이드는 PIE가 아닌 실행 파일을 거부한다("Android only supports position-independent executables") → x86에서 musttail의 주소 계산 비용을 없앤 no-pie 방식을 쓸 수 없다.
  - clang(AArch64)은 마이크로벤치마크의 switch를 점프 테이블이 아니라 비교 이진 트리로 만든다(간접 분기 0개, 조건 분기 3배, 예측 실패 380M 대 cgoto 237M, 사이클 +21%). 같은 clang이 x86에서는 점프 테이블 + 핸들러별 복제를 만든다.
  - Termux의 `gcc`는 clang의 별칭이다 → 안드로이드에서는 gcc 비교 불가. (빌드 스크립트가 이 경우를 건너뛰도록 수정)
  - 일반 앱(Termux) 권한으로는 SELinux가 perf_event_open을 막는다. `adb shell setprop security.perf_harden 0` 후 adb shell 사용자로 실행해야 카운터를 읽을 수 있다. `simpleperf`는 앱 권한에서 자식 명령 실행을 거부해 자체 도구(`bench/pstat.c`)를 씀.
  - 쓸 수 있는 ARM PMU 이벤트: BR_RETIRED(0x21), BR_MIS_PRED_RETIRED(0x22), BR_MIS_PRED(0x10), BR_INDIRECT_SPEC(0x7a). 간접 분기 예측 실패 전용 이벤트는 sysfs에 없지만 탐침으로 찾았다: Oryon raw 0x8117, Cortex-A76 raw 0x118(6.2c, 3.2).
  - clang 21은 AArch64에서도 musttail과 preserve_none을 지원한다.
- 3.3 측정 절차: 코어 고정, 실행 순서 무작위, 쿨다운, 설정 감시, 클럭 검사, 5회 반복, perf 카운터(사이클, 명령어, 분기, 예측 실패; 조건/간접 분리). 사이클을 주 지표로 쓴 이유(클럭 고정 시 시간과 비례, 편차 0.1% 수준).
- 3.3.1 통계(`analysis/bootstrap.py`, `analysis/ci_all.sh` → `results/analysis/ci_all.txt`): ✅
  - 벤치마크마다 반복 측정값의 중앙값(pyperf는 평균), 기준 대비 비율의 기하평균.
  - 부트스트랩 95% 구간 두 가지(10,000회): **잡음 구간**(벤치마크마다 반복값만 재추출 → 측정 잡음보다 큰가), **벤치마크 구간**(벤치마크도 재추출 → 다른 벤치마크 집합에서도 같은 부호인가).
  - 본문에는 벤치마크 구간을 쓴다. 반복 3~5회라 잡음 구간은 과소추정될 수 있음을 밝힌다.
- 3.4 tail call 변환 도구 → 4장에서 상세.
- 3.5 재현성: `bench/all.sh`, 원본 데이터와 스크립트 공개(아티팩트).

## 4. Converting Interpreters to Tail-Call Dispatch (C2)

- 4.1 Lua: `vmbreak` → 디스패치 tail call, `goto` 5종 → 공유 블록 tail call. 상태 8개를 레지스터 인자 6개로(trap을 명령어와 묶음, cl은 재계산).
- 4.2 WAMR: 전처리 후 분할(`#if` 해소), 상태 변수 자동 분류(쓰기 전 읽기 → 구조체, 나머지 → 지역), 내부 레이블에서 함수 분할, 로더 테이블에 함수 포인터.
- 4.3 preserve_none 변형과 그 효과(핸들러당 push/pop 10~12개 → 2개).
- 4.4 검증: Lua 공식 테스트 스위트 통과(8개 변형), WAMR 프로그램 11개 출력 일치. ✅ WAMR 공식 스펙 테스트(`tests/wamr-test-suites`의 `all.py`, spec 커밋 f3a0e06 + WAMR의 ignore_cases.patch, fast interp, x86-64)도 8개 변형(switch/cgoto/tail/tailpn × gcc/clang) 모두 **85/85 통과**(2026-11-23, `analysis/wamr_spec.sh`, `results/analysis/wamr_spec.txt`). 테스트용 빌드는 스위트의 빌드 옵션(SPEC_TEST=1 등)을 더해 다시 만든 것이고, tail 변형은 같은 변환기로 다시 생성됐다(핸들러 187개).
- 표: 변환 규모(핸들러 수, 상태 변수 분류, 생성 코드 줄 수).

## 5. Results

### 5.1 분기 예측은 차이를 만들지 않는다 (Rohou 재확인)

- 마이크로벤치마크 i9 -O2: 예측 실패 195~208M로 모든 방식이 비슷(이상 사례 제외). ✅
- 예측 실패를 분해하면 정상 바이너리는 99.4%가 콜라츠 홀짝 판정 조건 분기. 간접 점프 예측 실패는 switch(gcc, 간접 점프 1개)조차 0.4M. ✅
- ARM(Oryon, clang 21, -O3): cgoto 237M, musttail 198M, musttail_args 200M로 비슷하다. 예외는 switch(380M)인데, 이건 예측기 문제가 아니라 clang이 switch를 비교 트리로 만들어 조건 분기가 3배로 늘었기 때문이다(5.2). ✅
- 그림: 방식별 예측 실패(조건/간접 막대).

### 5.2 차이를 만드는 것은 컴파일러가 만든 디스패치 코드다

- gcc switch는 cgoto보다 +32%(i9 -O2), 명령어 53.1G 대 35.9G. clang switch는 +2.3%: clang이 간접 점프를 핸들러 10곳에 복제(사실상 자동 cgoto). ✅
- Elhage 2025의 clang 19 회귀와 연결: 이 복제는 보장되지 않는다.
- musttail의 명령어 증가(PIE의 `lea` 재계산), no-pie/인자 전달로 제거. ✅
- ARM에서는 같은 clang이 전혀 다른 디스패치 코드를 만든다. ✅
  - switch: 점프 테이블 대신 `cmp`/`b.le`/`b.gt` 비교 이진 트리. 간접 분기 0개, 분기 23.95G(cgoto 7.81G), 예측 실패 380M(cgoto 237M), 사이클 +21.5%.
  - 안드로이드는 PIE를 강제한다 → no-pie로 주소 계산을 없애는 방법을 쓸 수 없다.
  - 그런데도 tail call이 cgoto를 이긴다: musttail(PIE) −3.0%, musttail_args −4.1%(-O3, 사이클). musttail은 명령어가 46% 많지만(73.4G 대 50.5G) IPC가 2.68로 cgoto(1.79)보다 높다. 넓은 코어가 추가 명령을 흡수한다.
  - 인텔과 순위가 뒤집힌다: 인텔에서는 cgoto(gcc)가 1위, Oryon에서는 tail call이 1위(clang끼리 비교).
  - **같은 코드, 다른 코어 폭(Cortex-A76, 파이 5)**: 파이의 clang 21.1.8은 갤럭시의 Termux clang과 같은 버전이라 명령어 수가 똑같다(-O3 musttail 73.4G, cgoto 50.5G). 그런데 A76(좁은 코어)에서는 musttail이 cgoto clang보다 **+13%**(IPC 2.06 대 1.60)로, Oryon의 −3.0%와 반대다. 늘어난 명령어를 넓은 코어는 흡수하고 좁은 코어는 못 한다는 C3를, 명령어 흐름이 동일한 조건에서 보여 준다. ✅ (`results/cortex-a76_O*_raw.txt`)
  - A76에서는 gcc 15도 switch를 비교 트리로 만든다(간접 분기 0, -O2/-O3에서 cgoto gcc 대비 +37~42%, clang +43~49%). -O2/-O3 1위는 cgoto gcc, cgoto clang +1.5~5.6%, musttail gcc +6.5~10.2%.
  - A76 -O2의 musttail clang +62.5%(예측 실패 783M, cgoto의 2배 이상)는 원래 배치(seed 0)가 간접 예측 붕괴 배치이기 때문이다(6.2d). -O3에서는 +19.6%(예측 실패 정상).
- 표: 방식 × 컴파일러, 사이클/명령어/IPC/예측 실패. (+ ARM 열)

### 5.3 실제 인터프리터에서는 차이가 작아진다

- Lua(i9, 시드 고정, cgoto gcc 대비 사이클 기하평균): switch gcc −1.4%, switch clang −2.9%, cgoto clang −4.3%, tail gcc +5.6%, tail clang +1.4%, tailpn gcc −1.1%, **tailpn clang −7.4%**. ✅
- Lua, clang끼리(cgoto clang 대비 사이클 기하평균): ✅
  - i9(clang 23, 5회): switch +1.5%, tail +6.0%, **tailpn −3.2%**
  - 갤럭시 Oryon(clang 21, 3회): switch +3.0%, tail +2.0%, **tailpn −6.0%**(14개 벤치마크 전부에서 cgoto보다 빠름, −0.3%~−15.8%)
  - Cortex-A76(파이 5, -O2, 5회, cgoto gcc 대비, 벤치마크 95% 구간): cgoto clang +4.5% [+2.4, +6.3], switch gcc +3.2% [+0.1, +5.7], switch clang +6.8%, **tail gcc +16.1%, tail clang +17.2%**, tailpn clang +4.1%(cgoto clang 대비 −0.4%, 구분 안 됨). → **cgoto gcc 1위, i5와 같은 패턴**(좁은 코어는 tail call의 명령어 증가를 그대로 사이클로 낸다). 넓은 코어(i9, Oryon)에서는 tailpn이 1위였다. ✅ (`results/lua_cortex-a76_raw.txt`)
  - 두 CPU 모두 tailpn 1위, preserve_none 없는 tail은 cgoto보다 느림.
- **큰 인터프리터에서는 컴파일러가 cgoto의 점프를 합친다.** Lua `luaV_execute`의 간접 점프 수: switch 1(모든 경우), cgoto gcc(x86) **6**, cgoto clang(x86) **46**, cgoto clang 21(AArch64, 갤럭시) **1**(clang 23 AArch64는 90). opcode는 83개. → cgoto라고 써도 핸들러별 디스패치가 보장되지 않는다. 마이크로벤치마크(핸들러 7개)에서는 9~10개로 복제됐다. Lua에서 cgoto와 switch의 차이가 작은 이유. ✅
  - 핸들러별 디스패치를 구조적으로 보장하는 것은 tail call뿐(핸들러마다 별도 함수 → 합칠 수 없음).
  - Elhage 2025(clang 19가 CPython의 computed goto 점프 복제를 멈춤)와 같은 계열의 현상.
  - 세 인터프리터 비교(디스패치 루프의 간접 점프 수): ✅

    | 인터프리터 | switch | cgoto | tail call |
    |---|---|---|---|
    | Lua (83 opcode) | 1 | gcc 6 / clang 46 / ARM clang 1 | 핸들러마다 |
    | WAMR (~200) | 2 | 216~228 | 182개 핸들러, 180~203 |
    | CPython (~240), PGO 없음 | 1 | 221~260 | 242개 핸들러, 255~258 |
    | CPython, PGO+LTO | 2~3 | 223~259 | 248~259 |

  - **Lua만 합쳐지는 이유(2026-11-23 확인, `analysis/dispatch_tails.py`)**: ✅
    - 처음 가설("훅 검사 때문에 디스패치 꼬리가 커서")은 **기각**. 훅 검사를 분기 없이 인덱스에 섞은 변형(`cgotobf`, `targets/lua/patch_bf.py`, 공식 테스트 통과)도 그대로 합쳐졌다(gcc 6~7, clang 17~19). 꼬리 복제 한도를 올려도 거의 안 변함(gcc 33).
    - 합치는 주체는 **꼬리 병합**이다. 끄면 핸들러별 점프가 돌아온다(`cgotonm`, 공식 테스트 통과):

      | Lua lvm.c, -O2 | 점프 수 |
      |---|---|
      | gcc 기본 / `-fno-crossjumping` | 6 / **78** |
      | clang 기본 / `-mllvm -enable-tail-merge=false` | 46 / **157** |

    - 조건 1, **꼬리가 똑같아야 한다**: Lua는 명령어가 4바이트 고정이고 테이블 주소가 레지스터에 있어 디스패치 꼬리가 바이트 단위로 같다(clang 병합 전 157개 중 155개 동일). WAMR은 꼬리에 피연산자 길이가 들어가 제각각(228개 중 163종) → 병합 한도를 없애도 228 → 196, 216 → 214로 조금만 줄어든다.
    - 조건 2, **컴파일 시간 한도 안이어야 한다**: gcc는 진입 간선이 100개(`max-crossjump-edges`) 이하인 블록만 cross-jumping 한다. Lua의 디스패치 지점은 78개(한도 75에서 78 사이에서 결과가 바뀜) → 한도 안 → 병합. CPython은 동일 꼬리 묶음이 66~77개로 Lua만큼 많지만 디스패치 지점이 260개라 한도 밖 → 살아남는다. 한도를 1000으로 올리면 **CPython도 260 → 36개로 합쳐진다.**
    - **clang의 순서는 "모으고 → 병합 → 복제"다(2026-11-23, `-mllvm -print-after`로 단계별 점프 수 추적).** 프런트엔드가 computed goto를 `indirectbr` 하나로 모으고, 점프는 레지스터 할당 **뒤** tail duplication과 블록 배치에서 복제된다(LLVM PR #150911, 2025). 꼬리 병합(BranchFolder)은 그 **앞**에서 핸들러 끝을 합쳐 디스패치 블록의 선행 블록 수를 줄인다 → 복제 개수 = 병합 뒤 남은 선행 블록 수. ✅

      | clang 23, -O2 | early tail dup | branch folder | tail dup | block placement(최종) |
      |---|---|---|---|---|
      | Lua 기본 / 병합 끔 | 1 / 1 | 1 / 1 | 24 / 79 | **46 / 157** |
      | CPython 기본 / 병합 끔 | 1 / 1 | 1 / 1 | 198 / 291 | **221 / 341** |

    - 그래서 clang에서 CPython이 덜 합쳐지는 이유는 **핸들러 끝이 제각각이라서**다. 병합 전 디스패치 직전 9개 명령어(k=8)가 같은 묶음의 최대 크기: Lua 29개(157개 중 98종), CPython 8개(341개 중 248종). CPython은 인라인 캐시 때문에 명령어 길이가 달라 `next_instr` 오프셋이 핸들러마다 다르다. 최종 바이너리의 "똑같은 꼬리 77개"는 복제 단계가 같은 디스패치 블록을 붙여 넣어서 생긴 것이라 병합 대상이 아니다(병합이 먼저 끝남).
    - gcc도 순서는 같다(cross-jumping → 계산된 goto 복제). 차이는 gcc의 간선 한도(100)가 CPython(260)을 통째로 제외한다는 점.
    - 해석: computed goto의 핸들러별 디스패치는 프로그래머가 보장하는 게 아니라, 바이트코드 형식(고정 폭이면 위험)과 컴파일러의 컴파일 시간 한도라는 **우연**에 달려 있다. 고정 폭 바이트코드 + 디스패치 지점 100개 미만이면 gcc가 합친다.
    - 실무 지침 후보: 인터프리터 함수에만 `-fno-crossjumping`(gcc) / `-mllvm -enable-tail-merge=false`(clang). 또는 tail call(함수가 나뉘어 합칠 수 없음).
  - **컴파일러 버전 축(2026-11-23, `analysis/compiler_versions.py`, Compiler Explorer로 컴파일만, `results/analysis/compiler_versions.txt`)**: 같은 Lua 5.4.8 lvm.c, `-O2 -fPIE`, cgoto 점프 수(괄호: 꼬리 병합 끔). 로컬 gcc 16.2/clang 23.1과 값이 정확히 같아 방법을 검증함. ✅

    | 컴파일러 | x86-64 | AArch64 |
    |---|---|---|
    | gcc 4.4 | 1 (1) | – |
    | gcc 4.9~6 | 4~7 (78) | 3~5 (78) |
    | gcc 7~9 | 9~10 (79) | 14~15 (154) |
    | gcc 10~15 | 5 (78) | 13~15 (156~157) |
    | gcc 16 | 6 (78) | 7 (157) |
    | clang 3.5~11 | **78 (78)** | 78 (78, 9~11) |
    | clang 12~21 | **1 (1)** | **1 (1)** |
    | clang 22 | 35 (155) | 90 (142) |
    | clang 23 | 46 (157) | 90 (142) |

    - **같은 소스, 같은 `-O2`에서 핸들러별 점프가 1개에서 157개까지 컴파일러 버전에 따라 바뀐다.** clang은 3.5~11에서 완전 복제(78) → 12~21에서 완전 통합(1) → 22부터 다시 복제. "cgoto = 핸들러별 디스패치"라는 전제는 어느 버전에서도 보장되지 않는다.
    - clang 12~21에서 1개가 되는 원인(LLVM 옵션 실험, `results/analysis/compiler_knobs.txt`): 디스패치 블록이 간접 분기 블록 복제 한도 `tail-dup-indirect-size`(20명령어)를 넘기 때문. 한도를 200으로 올리면 clang 12, 18, 21(x86, AArch64 모두)에서 78개로 돌아온다. clang 19는 여기에 LLVM 19에서 생긴 선행/후속 블록 수 한도(`tail-dup-pred-size`/`succ-size`)까지 걸려 둘 다 올려야 78개(Elhage 2025가 CPython에서 본 clang 19 회귀와 같은 한도). clang 21에서는 이 두 번째 한도가 computed goto에 대해 풀려 첫 번째 한도만 남는다(LLVM PR #114990과 맞음). LLVM 12에서 정확히 무엇이 바뀌어 Lua 디스패치 블록이 한도를 넘게 됐는지는 미확인.
    - gcc도 순서가 같다: RTL 덤프에서 점프는 `compgotos` 단계(계산된 goto 복제) 직전까지 1개이고, 거기서 6개(병합 끔: 78개)로 복제된다. 앞선 cross-jumping이 복제할 선행 블록 수를 정한다.
    - ARM 32비트(로컬 arm-none-eabi-gcc 16.2, clang 23, `analysis/arm_jumps.sh`, `results/analysis/arm_jumps.txt`): gcc Thumb-2 3개(병합 끔 79), ARM 모드 4개(122), clang Thumb-2 55개(79). 아키텍처가 바뀌어도 gcc는 합치고 clang은 일부만 합친다.
    - **갤럭시 결과의 해석이 바뀐다**: 갤럭시(Termux clang 21)의 cgoto clang은 점프 1개, 즉 switch와 같은 단일 디스패치였다. "갤럭시 tailpn −6.0%"는 복제된 cgoto가 아니라 **통합된 cgoto**와의 비교다. 갤럭시 Lua에서 switch가 cgoto보다 3.0%만 느렸던 것도 이것으로 설명된다. 본문에 반드시 적는다.
  - **성능(i9, -O2, 5회, `results/lua-merge_i9-14900k_raw.txt`, 편차 중앙값 0.38%)**: ✅ i9 / ✅ i5(아래)
    - gcc: 점프 6 → 78(`cgotonm`)이면 **−4.7% [−7.4, −2.5], 14개 전부 승.** cgoto gcc가 cgoto clang 수준(−4.1%)이 되고, tailpn gcc보다 3.6% [2.0, 5.2] 빨라진다. → Lua에서 gcc cgoto가 clang cgoto보다 느렸던 이유는 점프 병합.
    - clang: 46 → 157은 −0.2% [−4.5, +3.9]로 차이 없음. 어느 정도 복제되면(46개) 더 복제해도 이득이 없다.
    - **이득은 분기 예측이 아니다**: Lua의 예측 실패는 1,000명령당 0.38개(사이클의 약 3%)뿐이고 `cgotonm` gcc에서 0.36개로 거의 안 변한다. 대신 명령어 −2.1%, 분기 −9.5%(공유 디스패치 블록으로 가는 무조건 점프가 사라짐). Mandelbrot은 사이클 −18.3%인데 예측 실패는 −3.7%. clang `cgotonm`은 예측 실패가 +14.6% 늘었는데 사이클은 그대로. → 복제의 이득은 고전적 설명(Ertl & Gregg: 예측 향상)이 아니라 프런트엔드(점프 하나 제거)에서 온다. 제목과 맞는 결과.
    - 분기 없는 훅 검사(`cgotobf`)는 손해: gcc +4.6%, clang +1.7%(명령어 +4.9%, 점프 수는 거의 그대로).
    - **clang에서 tailpn의 우위는 디스패치 구조 때문이 아니다**: 점프를 모두 복제한 `cgotonm` clang보다도 tailpn이 −3.5% [−6.0, −1.2] 빠르다. 명령어는 +3.1% 많지만 IPC가 약 7% 높다 → top-down으로 확인(아래).
  - **top-down(TMA), i9, Lua 14개 벤치마크 평균(`analysis/topdown.sh`, `analysis/topdown_summary.py`, `results/topdown_lua_i9-14900k.txt`, 요약 `results/analysis/topdown_lua_i9-14900k_summary.txt`; 2회, 그룹마다 따로 실행해 멀티플렉싱 없음)**: ✅ i9, i5(아래 "top-down i5")
    - Lua는 **retiring이 61~79%**, bad speculation은 6~8%(분기 예측 실패 5~6%)뿐. DSB(µop 캐시) 공급률 96~98%, I-캐시 정체는 사이클의 0.3% 미만 → 코드 크기나 캐시 문제는 없다.
    - gcc cgoto → `cgotonm`(−4.7%): **front-end bound −6.5%p(fetch bandwidth −4.3, latency −2.2)**, bad speculation +0.5%p. → 복제의 이득은 예측이 아니라 프런트엔드 공급(공유 디스패치 블록으로 가는 taken 점프 제거)이라는 5.3의 결론을 top-down이 직접 확인.
    - cgoto gcc 대 cgoto clang(−4.1%)의 차이도 같은 곳: clang은 front-end bound −7.5%p(fetch bandwidth −5.6). Lua에서 gcc cgoto가 느린 이유 = 프런트엔드.
    - clang tailpn 대 `cgotonm` clang(−3.6%, 명령어 +3.1%): retiring +5.0%p, front-end −1.8, backend −2.3(core −1.7, memory −0.6), bad speculation −0.8. 한 군데가 아니라 **세 병목이 고르게 조금씩 줄어든다** → 핸들러를 작은 함수로 나눈 덕에 생기는 스케줄링/레지스터 할당 차이로 해석(병목 하나로 설명되지 않음).
    - preserve_none의 효과(tail → tailpn): 명령어 **−15%**(clang −14.9%, gcc −15.2%; callee-saved 레지스터 저장·복원 제거), 사이클 −8.6%/−6.5%. preserve_none 없는 tail은 retiring 79%로 "바쁘지만 쓸데없는 일"을 한다(저장 명령 비율 0.17/명령어 대 0.12).
    - 재현성: 같은 바이너리(cgoto, tailpn)를 이전 측정과 비교하면 기하평균 차이 0.1~0.6%. 벤치마크 단위로는 최대 ±7% 차이(환경 변수 크기 등 스택 배치 차이로 추정) → 비교는 같은 세션 안에서만 한다.
    - 실무 지침: gcc로 빌드하는 고정 폭 바이트코드 인터프리터는 인터프리터 파일에 `-fno-crossjumping`만 붙여도 약 5% 이득(i9), 2.4%(i5).
  - **성능(i5, -O2, 5회, `results/lua-merge_i5-1135g7_raw.txt`, 편차 중앙값 0.65%, load 중앙값 0.51)**: ✅
    - gcc `cgotonm`: **−2.4% [−4.3, −0.7], 11/14 승** → i9와 같은 방향, i5 전체 1위(cgoto gcc보다 빠름).
    - 예측 실패는 i5에서 더 많이 줄었는데(−12.6% 대 i9 −6.8%) 사이클 이득은 더 작다(−2.4% 대 −4.7%) → 이득이 예측에서 오지 않는다는 결론을 다시 뒷받침. 명령어 −2.1%, 분기 −9.4%는 i9와 같다.
    - clang `cgotonm`: +1.9% [+0.4, +3.7](i9는 −0.2%) → i5에서는 더 복제하면 오히려 손해(예측 실패 +24.7%).
    - `cgotobf`: gcc +4.1%, clang −0.2% → i9와 같이 이득 없음.
    - tailpn: gcc +7.1%(cgoto gcc 대비), clang +0.8%(cgoto clang 대비, 구분 안 됨), clang `cgotonm` 대비 −1.1% [−2.9, +0.3](i9 −3.5%).
    - **CPU에 따라 1위가 바뀌는 이유의 실마리**: tailpn gcc는 두 CPU 모두 명령어 +15.3%. i9는 이를 IPC로 흡수해 −1.3%, i5는 못 흡수해 +7.1%. → 더 넓은 코어(i9 Raptor Cove)에서는 명령어가 많은 tail call이 손해를 덜 본다. top-down i5로 확인 ✅(아래).
    - 이전 i5 -O2 측정과 재현: cgoto clang +2.6%(이전 +2.4%), tailpn clang +3.4%(+3.0%), tailpn gcc +7.1%(+7.4%).
  - **top-down i5(Tiger Lake, Lua 14개 평균, 2회; `results/topdown_lua_i5-1135g7.txt`, 요약 `results/analysis/topdown_lua_i5-1135g7_summary.txt`)**: ✅
    - 측정 주의: Tiger Lake는 2단계(L2)를 1단계와 따로 돌려야 하고, 그 실행은 멀티플렉싱(47~53%)된다. 이때 perf-metrics 비율(topdown-*)이 틀어진다(Richards: bad-spec 슬롯 13% → 44%, 그 결과 "분기 예측 실패 28% > bad speculation 11%" 같은 모순). → 1단계는 멀티플렉싱 없는 실행의 값을 쓰고, 2단계는 perf의 공식 그대로 "1단계 비율 × 원시 카운터 비율"로 다시 계산했다(`topdown_summary.py`; fetch latency는 원래 카운터만 쓰므로 perf 값과 일치 확인). i9는 2단계까지 고정 카운터라 해당 없음.
    - **두 CPU의 차이는 프런트엔드 손실의 크기다.** cgoto gcc의 front-end bound: i9 18.8%(fetch bandwidth 13.2) 대 i5 12.1%(9.1). tailpn gcc가 되찾는 것도 프런트엔드: i9는 −11.3%p → IPC 3.82 → 4.50(+18%)로 명령어 +15.3%를 흡수해 −1.3%. i5는 −3.8%p → IPC 3.30 → 3.57(+8%)에 그쳐 +7.1%.
    - 같은 패턴이 다른 쌍에도 그대로 나온다(cgoto gcc 대비, 명령어는 같은 바이너리라 두 CPU에서 같음):

      | 변형 | 명령어 | i9 front-end | i9 사이클 | i5 front-end | i5 사이클 |
      |---|---|---|---|---|---|
      | switch gcc | +7.2% | −7.9%p | −1.3% | −4.2%p | +0.5% |
      | cgoto clang | +6.0% | −7.5%p | −4.1% | −3.0%p | +2.2% |
      | tailpn clang | +8.2% | −10.6%p | −7.7% | −3.4%p | +2.7% |
      | tailpn gcc | +15.3% | −11.3%p | −1.3% | −3.8%p | +7.1% |

    - 해석: 변형들은 "명령어 수"와 "프런트엔드 손실" 두 가지로 갈린다. 6-wide인 i9(슬롯 6/사이클)에서는 taken 점프가 잦은 gcc cgoto의 공급이 할당 폭을 못 따라가 슬롯을 많이 잃고, 그걸 줄이는 변형이 명령어가 많아도 이긴다. 5-wide인 i5에서는 잃는 슬롯이 적어 명령어 수가 거의 그대로 사이클로 간다 → **"CPU마다 1위가 바뀐다"는 예측기가 아니라 코어 폭 대비 프런트엔드 공급으로 설명된다.** bad speculation은 i5가 10~12%(i9 6~8%)로 높지만 변형 사이 차이는 ±1.5%p 안.
    - gcc cgoto → `cgotonm`(−2.6%): front-end −3.5%p(fetch bandwidth −3.1), backend +3.8 → i9(−6.5%p)와 같은 방향, 절반 크기 = 사이클 이득의 비율(−2.6% 대 −4.7%)과 맞는다.
    - clang tailpn 대 `cgotonm` clang(−1.3%, 명령어 +3.1%): retiring +3.5%p, backend −2.2(core −1.9), bad speculation −1.2, front-end −0.1. i9에 있던 front-end 이득(−1.8)이 빠진 만큼 이득이 작다(i9 −3.6%).
    - preserve_none(tail → tailpn): 명령어 −15.0%(clang)/−15.4%(gcc), 사이클 −10.4%/−8.1%로 i9(−8.6%/−6.5%)보다 크다 → 명령어를 줄이는 변화는 좁은 코어에서 더 크게 듣는다. 위 해석과 같은 방향.
  - PGO는 점프 구조를 거의 바꾸지 않는다(cgoto 259/223, switch 1→2~3). → "PGO가 cgoto 이점을 없앤다"는 구조 변화가 아니라 배치/분기 가중치 개선 효과로 해석.
- Lua, CPU에 따라 1위가 바뀐다(cgoto gcc 대비, -O3): i9 tailpn clang −6.5%(1위), i5 cgoto gcc 1위(tailpn clang +4.7%, tail gcc/clang +16%). 갤럭시는 tailpn clang 1위. ✅
  - 신뢰구간 반영(벤치마크 구간): i9 -O3의 tailpn clang −6.5% [−10.1, −3.5]와 cgoto clang −6.3% [−10.0, −3.4], tailpn gcc −5.2%는 **구분되지 않는다** → "i9 -O3 1위"가 아니라 "clang 계열과 tailpn이 cgoto gcc보다 5~6% 빠르다"로 고쳐 쓴다.
  - i9 -O2 gcc끼리: switch −1.4% [−4.4, +1.3], tailpn −1.1% [−4.1, +1.3]는 cgoto와 구분 안 됨. preserve_none 없는 tail만 유의하게 느림(+5.6% [+3.3, +8.7]).
  - i9 -O2 clang끼리: tailpn −3.2% [−7.3, −0.0]은 경계선. tail +6.0% [+2.6, +9.1]은 유의.
  - i5: cgoto gcc 1위는 유지되지만 -O2에서 switch gcc(+1.1% [−0.6, +2.7]), -O3에서 cgoto clang(+0.9% [−1.1, +2.4])과는 구분 안 됨.
  - 갤럭시 tailpn −6.0% [−8.3, −3.4], 14개 전부 승 → 가장 확실한 결과.
  - i5 Lua -O2(앱을 끄고 재측정, 편차 중앙값 0.83%, load 0.55): switch gcc +1.1%, **cgoto gcc 1위**, tail gcc +17.0%, tailpn gcc +7.4%, switch clang +7.2%, cgoto clang +2.4%, tail clang +15.3%, tailpn clang +3.0%. -O3와 같은 결론. ✅
  - 처음 i5 -O2 측정은 데스크톱 앱 부하로 오염(편차 중앙값 9%)되어 폐기하고 재측정함 → 8절에 기록.
- CPython(i9, 시간 기하평균, pyperformance): ✅
  - PGO 없음(cgoto gcc 대비): switch gcc +5%, tail gcc ±0, switch clang +12%, cgoto clang +6%, tail clang +6%.
  - **PGO+LTO**(실제 배포 조건, cgoto gcc 대비): switch gcc −1%, tail gcc ±0, switch clang +2%, cgoto clang +5%(최하위), **tail clang −2%(1위)**.
  - 같은 컴파일러끼리(PGO+LTO): clang은 tail이 cgoto보다 7% 빠르고 switch도 2% 빠르다. gcc는 셋이 ±1%.
  - PGO 효과: switch +18~21%, cgoto +11~12%, tail +12%(gcc)/+21%(clang). PGO가 switch와 clang tail을 가장 많이 끌어올린다 → **PGO를 켜면 cgoto의 이점이 사라진다.**
  - CPython 개발자들의 "clang + PGO에서 tail call이 computed goto보다 약 5% 빠르다"를 재현(7%). PGO 없이는 재현되지 않음.
  - 신뢰구간(PGO+LTO, 벤치마크 구간): tail clang 대 cgoto clang −6.8% [−8.0, −5.5], 대 cgoto gcc −2.2% [−3.5, −0.8]. switch gcc도 cgoto gcc보다 −1.0% [−1.3, −0.6]로 유의하게 빠르다.
- WAMR(사이클, cgoto gcc 대비 기하평균, 8개 프로그램): ✅ (주의: c-ray는 빈 장면, 8절)
  - switch는 +60~108%. 단 WAMR의 switch 모드는 바이트코드 형식이 다름(cgoto 모드는 로딩 시 핸들러 주소를 바이트코드에 미리 기록) → 디스패치 비교에서 제외하고, 같은 형식인 cgoto/tail/tailpn끼리 비교.
  - i9 -O3: cgoto clang −5.8%, tail gcc −5.0%, **tailpn gcc −6.5%**, tail clang ±0, tailpn clang −2.9%.
  - i5 -O3: cgoto clang +2.8%, tail gcc +2.9%, tailpn gcc +0.1%, tail clang +11.1%, tailpn clang +6.0%.
  - Cortex-A76 -O3(gcc 15, clang 21, 5회, c-ray는 x86과 같은 빈 장면): **tail gcc −4.6% [−6.7, −3.1]**(8개 전부 승), cgoto clang −2.3%, tailpn clang −1.3%, tail clang +1.2%, switch clang +28%, switch gcc +57%. i9와 비슷한 구도. tailpn gcc는 없음(gcc 15가 AArch64에서 preserve_none 미지원). ✅ (`results/wamr_cortex-a76_raw.txt`)
  - c-ray 빈 장면 대 정상 장면(A76): 순위가 같고 차이는 2~7%p(tail gcc −5.1% 대 −7.4%, switch gcc +60.9% 대 +54.7%) → x86 c-ray 결함(8절)이 결론을 바꿀 가능성은 낮다.
  - cgoto와 tail call은 ±7% 안에서 비슷하고 우열은 CPU에 따라 갈린다(i9는 tail 쪽, i5는 cgoto 쪽). preserve_none은 모든 경우 1.5~5%p 이득.
  - 신뢰구간: i9 -O3의 cgoto clang, tail gcc, tailpn gcc(−5~−6.5%)는 유의. i9 -O2에서는 cgoto clang(−5.7%)만 유의하고 tail 계열은 대부분 구분 안 됨. 프로그램이 8개라 벤치마크 구간이 넓다.
  - 자동 변환한 tail call 인터프리터가 수작업 cgoto와 대등 → C2(변환 도구)의 실용성 근거.
  - 실제 인터프리터(Lua, WAMR)에서는 마이크로벤치마크 같은 -O3 예측 실패 폭증이 관찰되지 않았다.
- 벤치마크별 편차가 크다(산술 위주에서 switch/tailpn 유리, Sieve에서 tail 불리). ✅ 원인: 명령어 증가량과 기준(cgoto)의 프런트엔드 여유 두 가지로 대부분 설명된다(Lua 14개 × 6개 변형 쌍 = 84개 비교, top-down 데이터, `topdown_summary.py --bench`).
  - i5: Δ사이클 ≈ 0.50 × Δ명령어(R² = 0.75). 프런트엔드 여유를 더해도 설명력이 늘지 않는다 → 좁은 코어는 늘어난 명령어를 그대로 사이클로 낸다.
  - i9: 명령어만으로는 R² = 0.26, 기준의 프런트엔드 병목 비율을 더하면 0.54(Δ사이클 ≈ 0.27 × Δ명령어 − 0.40 × FE_cgoto). Mandelbrot(cgoto의 FE 30~35%, 대부분 대역폭)과 NBody에서는 다른 방식이 명령어를 더 써도 이긴다(tailpn clang −23%). Sieve(FE 5%)는 tail call의 명령어 증가가 가장 커서(+34~52%) 가장 손해다(+17~21%).
  - 모델 밖 잔차가 큰 경우: tailpn clang의 Mandelbrot(−14%p)·Permute·Towers(core bound −6%p; 재귀 호출이 많아 preserve_none의 호출 비용 감소로 추정), tail clang의 Sieve(+10%p).
  - C3("코어 폭 대비 프런트엔드 손실")과 같은 그림이 벤치마크 단위에서도 성립한다.
- 그림: 인터프리터별 기하평균 + 벤치마크별 분포.

### 5.4 최적화 단계

- 마이크로벤치마크 musttail 대 cgoto(같은 컴파일러, 사이클, `results/<cpu>_O{0,1}_summary.csv`): -O0에서는 두 컴파일러 모두 musttail이 빠르다(i9 gcc −23.8%, clang −44.5%; i5 −19.0%, −26.0%). **-O1에서는 gcc만 빠르고(i9 −20.0%, i5 −12.7%) clang은 오히려 느리다(+16.5%, +8.5%)** — clang은 -O1에서 이미 cgoto 점프를 10개로 복제하기 때문. 즉 이득은 "tail call 자체"가 아니라 컴파일러가 복제를 안 할 때 구조를 보장하는 데서 온다(제목과 맞음). ✅ 데이터 / ✅ 원인(-O0은 가설 단계) (top-down, `results/topdown_micro_i9-14900k.txt`, 요약 `results/analysis/topdown_micro_i9-14900k_summary.txt`):
  - **-O1: 메모리 접근 수는 모든 변형이 똑같다**(load 29.15G, store 3.64G). 차이는 디스패치 구조: gcc는 -O1에서 computed goto를 복제하지 않아(`compgotos`는 -O2 이상) cgoto/switch gcc의 간접 점프가 1개 → **front-end bound 59~61%**(clang -O1은 점프 10개, 31~39%). tail call은 최적화 수준과 무관하게 핸들러별 디스패치를 보장 → gcc musttail −20%. "구조 보장"이 -O1에서 가장 크게 드러난다.
  - **-O0: 메모리 접근 수로는 설명이 안 된다.** gcc는 musttail이 load −34%(58.3G → 38.5G)지만, clang musttail은 load −6%, store **+31%**인데도 cgoto clang보다 45% 빠르다. cgoto/switch는 backend(core) bound 30~45%, musttail은 3~11%. TMA 3단계(i9, 대략치): core bound의 대부분이 ports utilization(30.0% 대 12.6%) = 명령어 수준 병렬성 부족.
  - **-O0 구조**: -O0에서는 꼬리 복제를 하지 않아 cgoto의 간접 점프가 gcc·clang 모두 **1개**다(clang은 목적지를 스택 `[rbp-24]`에 저장한 뒤 공용 블록에서 다시 읽어 `jmp`). musttail은 핸들러마다 7개. 그러나 -O0의 간접 예측 실패는 모든 변형에서 디스패치당 0.002 미만이라 예측은 원인이 아니다.
  - **"스택 슬롯을 통한 의존 사슬" 가설은 반박됨**(지연 주입, `analysis/latency_inject.sh`, i9, `results/analysis/latency_inject{,_val}_i9-14900k_summary.txt`): 사슬 위에 3사이클짜리 `imul R,R,1`을 k개 넣고, 대조군으로 같은 수의 독립 `imul`을 넣었다. 사슬이 병목이면 첫 주입부터 주입당 +3사이클이어야 한다.
    - pc 사슬(`pc += 3` 지점): cgoto clang은 k=1에서 주입당 1.04사이클이고, 한계 비용이 3에 이르는 것은 k≈6 이후다 → 여유가 있다. 여유는 오히려 musttail clang(k≈3에서 3에 도달)보다 크다.
    - VM 레지스터 값 사슬(`ram[]` 저장 직전): cgoto clang 주입당 0.4~1.1사이클로 대조군(0.05~0.6)과 비슷하다 → 병목 아님.
    - clang musttail은 핸들러마다 pc를 `[rbp-8]`에 저장했다 다시 읽는다(전달 2회). 그런데도 디스패치당 6.2사이클이다. 고전적인 4~5사이클 전달이면 불가능한 값이라, 고정된 저장→적재 쌍에는 빠른 전달(메모리 리네이밍)이 쓰이는 것으로 보인다(추정).
    - 주의: gcc -O0 코드는 배율 LEA가 많아 `imul`과 포트 1을 다툰다(대조군만으로 주입당 1.1~1.5사이클). gcc 쪽 기울기는 대조군과의 차로만 본다. cgoto gcc의 k=2에서는 사슬과 대조군이 모두 +76~78%였는데, 코드 크기에 따른 배치 효과다.
  - **실제로 보이는 것**(`analysis/o0_ports.sh`, `results/analysis/o0_ports_i9-14900k_summary.txt`, 멀티플렉싱 없음): clang cgoto와 musttail은 **실행 uop 수가 같다**(14.2G 대 13.9G). 그런데 사이클당 uop이 2.67 대 4.60이고, 4개 이상 실행한 사이클이 32% 대 70%다. 메모리 순서 위반 machine clear가 2.36M 대 0.075M(31배)이고, 적재 대기 사이클은 8.3% 대 2.8%다. gcc도 같은 방향이지만 폭이 작다(0.98M 대 0.21M, 3.0% 대 0.8%). 저장 전달 차단, 4K 별칭, 저장 버퍼 포화는 모두 0. clear의 복구 비용 자체는 작다(복구 사이클 2.4% 대 3.9%).
  - 결론: -O0 cgoto의 손해는 사슬 지연이 아니라 낮은 실행 병렬성이다. 남은 가설은 "큰 함수 하나에서 메모리 의존 예측기가 적재를 보수적으로 붙잡는다"이고, 직접 확인은 하지 못했다. -O0은 실사용 수준이 아니므로 논문에서는 관찰과 반박된 가설까지만 쓴다.
  - **Cortex-A76**(사이클, cgoto 대비): -O0 musttail gcc **−23.0%**(x86과 같은 방향), 그런데 **musttail clang +67%**(cgoto clang 대비 +34%; x86은 −26~−45%) → -O0 결과는 CPU에 따라 방향까지 바뀐다. -O1 musttail gcc −15.5%(x86 −13~−20%, 같은 구도). musttail clang은 cgoto clang 대비 **+63%**(x86 +8.5~+16.5%)인데, A76 -O1의 원래 배치가 간접 예측 붕괴 배치라(예측 실패 783M, -O2와 같은 코드·같은 배치) 부풀려진 값이다 → 배치 분포 없이는 해석 불가. (정정 2026-11-24: 예전 줄은 cgoto gcc 대비 +5.2%를 x86의 같은 컴파일러 대비 수치와 나란히 놓은 오류)
  - **-O 단계별 A76 붕괴 가능성**(6.2d): -O1·-O2는 jeven 디스패치를 하나로 합쳐(`tbnz … b … br`) 붕괴 가능, -O3는 갈래마다 복제(`tbnz … br … br`). ✅ 파이 clang 21 -O3 배치 101개 × 2변형: **붕괴 0/202**(`results/analysis/layoutdist_cortex-a76_O3.txt`), 사이클·명령어가 "-O2 + `-tail-dup-size=4`"와 사실상 같다(musttail 6.170G 대 6.167G, 명령어 13.109G로 동일) → 이 코드에서 -O2와 -O3의 차이는 꼬리 복제 하나뿐.
  - **i5 재현**(`results/topdown_micro_i5-1135g7.txt`, 요약 `results/analysis/topdown_micro_i5-1135g7_summary.txt`, 1회, 2단계는 위 Lua i5처럼 재계산): 같은 메커니즘, 폭은 작다. 사이클 비율은 본 측정과 0.1~1.7%p 안에서 일치. -O1 gcc cgoto/switch는 front-end bound 49%/44%(i9 61/59), musttail gcc가 front-end −35%p로 −12.9%. -O0은 core bound가 cgoto/switch 12~29% 대 musttail 9~11%로 같은 구도. load/store 수는 같은 바이너리라 i9와 같다.
  - 기존 가설("상태를 레지스터로 넘긴다")은 -O1에서는 틀렸고(접근 수 동일), -O0에서도 접근 수 감소만으로는 부족하다.
- **실제 인터프리터에서 -O2 vs -O3** (`analysis/opt_levels.py`, `results/analysis/opt_levels.txt`; 변형별 -O3/-O2 사이클 기하평균, 벤치마크 부트스트랩 95% 구간; 두 수준은 다른 세션이라 ±0.6%는 잡음): ✅
  - Lua: 대부분 ±3% 안. i9에서는 gcc tail 계열이 -O3 덕을 본다(tail gcc −3.0% [−4.6, −1.5], tailpn gcc −4.8% [−7.5, −2.5]). switch clang은 오히려 +3.1%. i5에서는 -O3가 대체로 손해(switch gcc +3.3%, tailpn clang +2.5%, switch clang +2.3%, tail clang +1.5%, 모두 유의), 이득이 유의한 변형은 없다.
  - WAMR(기본 빌드가 -O3): switch clang만 크게 바뀐다(i9 −14.0%, i5 −12.0%). 디스패치 점프 수는 두 수준 모두 2개로 같다 → 디스패치 구조가 아닌 다른 코드 생성 차이. gcc tail 계열은 i9에서 −4.6~−6.2%(유의), i5에서는 −2%(구분 안 됨). cgoto는 ±1~3%.
  - 명령어 수 변화는 ±3% 안 → 차이는 대부분 IPC에서 온다.
  - 결론: 디스패치 방식 비교의 결론은 -O2와 -O3에서 같다(순위를 바꾸는 효과는 i5 Lua에서 1~3%p 수준). 단 WAMR의 switch clang처럼 한 변형만 크게 움직이는 경우가 있어 두 수준을 모두 보고한다.
  - 벤치마크별 편차 원인(Lua Sieve, Mandelbrot 등)은 5.3 끝에 정리. ✅

### 5.5 호출 규약: preserve_none

- Lua에서 tail → tailpn: clang +1.4% → −7.4%, gcc +5.6% → −1.1%. ✅
- gcc 16과 clang 23의 preserve_none은 같은 이름, 다른 ABI(레지스터 인자 6개 대 8개 이상). ✅
- CPython은 인자를 6개로 맞춰 둘 다에서 동작.

## 6. Layout Sensitivity (C4)

- 6.1 사례: clang -O3 musttail의 예측 실패 1.8~2.9배, 사이클 +39~49%(두 CPU). ✅
  - 늘어난 실패는 전부 간접 점프(388.6M 대 정상 0.1~1.5M), 그것도 목적지가 하나뿐인 점프 두 개. ✅
  - 핸들러를 1바이트 밀면 사라진다. 32개 위치 중 2개(0, 8바이트)에서만 발생. ✅
    - 방법 표기 주의(`analysis/layout_sweep.sh`): "밀기"는 jeven/jnei 함수 레이블 **바로 뒤**에 K바이트 nop을 넣는 것이라, nop이 핸들러에 들어올 때마다 실행된다(본문이 K바이트 이동 + nop 실행). nop은 분기가 아니어서 간접 예측기의 이력에는 들어가지 않으므로 "배치 탓" 해석은 유지되지만, 논문에는 이렇게 정확히 적는다. 실행되지 않는 패딩만으로도 붕괴가 생긴다는 근거는 6.2a(fixed)에 있다.
  - 해석: 예측기 내부에서 두 분기의 항목이 충돌(정확한 규칙은 비공개 구조라 미확정).
  - ARM(Oryon)에서는 같은 소스의 clang -O3 musttail이 정상이다(예측 실패 198M, cgoto보다 빠름). 특정 CPU의 예측기와 특정 배치가 맞물린 현상이라는 해석과 맞는다. ✅
- 6.2a **배치 100개, 두 CPU**(콜라츠 범위 2백만, -O2, 8개 변형 × 101개 배치; `analysis/layoutdist_summary.py`, `results/analysis/layoutdist_summary.txt`): ✅ (2026-11-23 재측정 반영)
  - 데이터: 섭동 도구 버그(8절)로 패딩이 실행된 3개 변형(cgoto clang, musttail gcc, musttail_args gcc)은 고친 모드로 두 CPU에서 101개 배치를 재측정(`layoutdist_<cpu>_fixed.txt`). 나머지 5개는 두 모드의 배치가 같아 기존 데이터 사용. 16개 (CPU, 변형) 모두 배치끼리 실행 명령어 수가 같음을 확인 → 이제 정말 주소만 바뀐다.

  | 방식 | 붕괴(i5) | 붕괴(i9) | 합산 | (버그 있던 예전 값) |
  |---|---|---|---|---|
  | switch gcc(간접 점프 1개) | 0 / 101 | 0 / 101 | 0 / 202 (0%) | 0 / 202 |
  | cgoto | 5 / 202 | 1 / 202 | 6 / 404 (1.5%) | 3 / 404 (0.7%) |
  | switch clang(점프 10개 복제) | 3 / 101 | 0 / 101 | 3 / 202 (1.5%) | 3 / 202 |
  | tail call(musttail, musttail_args) | 11 / 404 | 7 / 404 | 18 / 808 (2.2%) | 26 / 808 (3.2%) |
  | **gcc 4개 변형** | 3 / 404 | 1 / 404 | **4 / 808 (0.5%)** | |
  | **clang 4개 변형** | 16 / 404 | 7 / 404 | **23 / 808 (2.8%)** | |

  - **예전 결론("cgoto가 tail call보다 붕괴 위험이 4분의 1, p = 0.008")은 철회.** 고친 데이터에서 cgoto 대 tail call은 p = 0.51, cgoto 대 clang switch는 p = 1.0 → 디스패치 방식으로는 구분되지 않는다. 예전 차이는 패딩이 실행된 변형(cgoto clang에서 붕괴가 줄고, gcc tail call에서 늘었음)에서 왔다.
  - **대신 컴파일러로 갈린다**: gcc 0.5% 대 clang 2.8%, Fisher p = 0.0003. 점프 하나짜리 switch gcc를 빼도 gcc 0.7%(4/606) 대 clang, p = 0.003. → C4도 제목("컴파일러가 문제")과 같은 방향이 된다.
  - clang 코드가 왜 더 취약한가(`analysis/collapse_geometry.py`, `results/analysis/collapse_geometry.json`): 측정한 배치 1,515개를 같은 절차로 다시 만들어 seed마다 모든 분기 주소를 기록했다. 보관한 붕괴 바이너리 30개와 간접 점프 주소가 전부 일치한다. ✅ (원인은 일부만 밝힘)
    - **디스패치 구조로는 설명되지 않는다.** jeven(목적지가 홀짝에 따라 바뀌는 유일한 핸들러)의 디스패치를 두 갈래로 복제하는지 하나로 합치는지가 후보였다. 그런데 갈래를 나누는 cgoto clang(5/202)과 switch clang(3/202)도 붕괴한다. 합치는 musttail_args gcc는 2/202, 전부 한 점프인 switch gcc는 0/202다. 구조가 같은 musttail_args끼리 비교해도(두 컴파일러 모두 jeven을 합침) clang 11/202 대 gcc 2/202다.
    - **충돌하는 두 점프의 주소만으로도 정해지지 않는다.** 붕괴 쌍(jeven 점프, shri 또는 muli 점프)의 하위 12비트에서 "일치해야 하는 비트 집합" 4,096가지를 전수로 찾았다. 가장 나은 조건인 "같은 256바이트 블록"은 musttail_args clang 붕괴 6건을 모두 잡지만 정상 배치의 절반도 같이 걸리고, musttail clang 붕괴 2건은 놓친다.
    - 해석: 붕괴는 배치의 결정적 함수다(같은 seed가 i5·i9에서 함께 붕괴). 그러나 두 점프 주소뿐 아니라 분기 이력까지 들어간 해시로 정해진다(이력으로 색인하는 간접 예측기와 맞음). 컴파일러 차이를 끝까지 설명하려면 예측기 해시를 역공학해야 해서 범위 밖이다. 논문에는 "구조가 아니라 코드 배치의 세부가 위험을 정하고, 그 함수는 단순한 주소 규칙이 아니다"까지 쓰고 한계로 적는다.
  - 유의하게 남는 방식 차이는 구조적인 것 하나뿐: 간접 점프가 하나인 switch gcc 0/202 대 tail call 18/808, p = 0.033.
  - 붕괴 원인(`analysis/catastrophe.sh`; 예전 32건 + 재측정에서 새로 생긴 8건, `catastrophe_i5-1135g7_fixed.txt`): 같은 형태 — **홀수 경로 위, 목적지가 고정된 간접 점프 두 개**가 예측 실패를 나눠 가진다(musttail_args: jeven 홀수 갈래 + shri, musttail: jeven + muli, cgoto clang: 디스패치 점프 두 개). 새 8건 중 7건이 이 쌍을 보이고(거리 68~273바이트), 1건은 1% 이상인 간접 점프가 하나뿐. 합쳐서 거리 68~388바이트, 같은 64바이트 블록 아님, XOR 패턴 없음 → 단순 주소 규칙 없음(예측기의 해시는 비공개).
  - 같은 배치가 두 CPU에서 함께 붕괴: i9 붕괴 8건 중 7건이 i5에서도 붕괴(clang tail call 7건 전부). i5가 더 취약(19건 대 8건).
  - 해석: 간접 점프가 하나뿐이면(gcc switch) 구조상 안전. 그 밖에는 방식보다 컴파일러가 낸 코드의 배치가 위험을 정한다.
- 6.2c **ARM(갤럭시 S25 Edge, Oryon) 배치 101개 × 4개 변형**(2026-11-23; `analysis/layout_dist_android.sh`, `results/analysis/layoutdist_galaxy-s25edge.txt`, 요약은 `layoutdist_summary.txt` 아래쪽): ✅
  - 방법: x86과 같은 소스, 같은 seed, 같은 패딩 규칙(perturb.py fixed, AArch64 경로). 빌드는 폰의 Termux clang 21 -O2, 측정은 adb shell에서 프라임 코어(cpu7)에 고정. clang만(Termux의 gcc는 clang). 404개 모두 정답 출력, 멀티플렉싱 없음, 배치끼리 명령어 수 동일(차이 3천 개 미만, 시작 코드 수준).
  - 간접 분기 예측 실패 이벤트: sysfs 목록에는 없어서 탐침 프로그램(`analysis/arm_pmu_probe.{c,sh}`)으로 이벤트 번호 1,792개를 훑었다. **raw 0x8117**이 무작위 8방향 간접 분기 7.00M, 무작위 조건 분기 347, 예측 가능한 간접 분기 366으로 간접 예측 실패만 센다(`results/analysis/arm_pmu_scan_galaxy-s25edge.txt`). 클럭을 고정할 수 없어 붕괴 판정은 이 수로, 비교는 사이클로 한다.
  - AArch64 clang의 switch는 간접 점프 0개(조건 분기 8개짜리 비교 트리) → 붕괴할 수 없는 대조군(최선~최악 2.3%).
  - **간접 점프 붕괴 0/404**(간접 예측 실패 최대 24만 회, x86 붕괴는 1천만~1.6억 회). clang 변형끼리 비교하면 i5 16/404(p = 0.00003), i9 7/404(p = 0.015)보다 유의하게 적다. → x86의 붕괴는 인텔 간접 예측기 고유의 현상이다.
  - **대신 다른 형태의 붕괴**: musttail clang만 9/101개 배치가 사이클 2.03~2.12배이고, 나머지는 모두 1.13배 이하(이분). cgoto, musttail_args, switch는 1.3배를 넘는 배치가 없다(최선~최악 5.9%, 14.6%, 2.3%).
  - 진단(`analysis/layout_diag_android.sh`, 느린 9개 대 정상 6개 × 3회, `results/analysis/layoutdiag_galaxy-s25edge_summary.txt`): 반복 편차 0.2% 이하로 배치의 결정적 효과다. 늘어난 5.29G 사이클 중 4.13G(78%)가 STALL_FRONTEND이고, STALL_BACKEND는 +0.07G다. 명령어 캐시 미스(약 6.7천)와 분기 예측 실패(+1.5M)는 그대로다. 그런데 버려진 투기 연산(OP_SPEC − OP_RETIRED)이 +7.6G(실행/완료 비율 1.6 → 2.1~2.5)다 → 예측 실패로 집계되지 않는 프런트엔드 재조정(예: 분기 목적지 버퍼 충돌로 인한 늦은 수정)으로 추정.
  - 기하 규칙: 로컬에서 같은 배치를 다시 만들어(`analysis/collapse_geometry_a64.py`; 실제 바이너리 = 로컬 오프셋 + 0x4840 확인) 분기 쌍의 같은 블록(32~512바이트) 조건을 훑었지만 깔끔히 가르는 조건은 없다. 로컬 오프셋으로는 "jeven 점프와 shri 점프가 같은 256바이트"가 8/9로 보였으나 실제 주소로는 5/9 대 정상 47/92라 버림.
  - 해석: 배치 위험은 CPU마다 형태가 다르다(인텔은 간접 예측 실패, Oryon은 프런트엔드 정체). 어느 쪽이든 특정 (컴파일러 코드, 배치) 조합에서 생기고, 디스패치 방식의 일반적 성질은 아니다. 이번 데이터에서 Oryon의 위험은 musttail clang에만 있었다.
- 6.2d **Cortex-A76(라즈베리 파이 5) 배치 101개 × 8개 변형 + 붕괴 규칙과 사전 예측 검증**(2026-11-24; `bench/pstat_all.sh`, `results/analysis/layoutdist_cortex-a76.txt`, 규칙 `analysis/a76_collapse_rule.py`, 결과 `results/analysis/a76_collapse_rule.txt`): ✅ **가장 강한 결과**
  - 간접 예측 실패 이벤트는 탐침으로 찾은 raw 0x118. 808개 모두 정답, 배치끼리 명령어 수 동일.
  - **붕괴는 clang tail call에만 있다**: musttail clang 35/101(원래 배치 seed 0 포함), musttail_args clang 29/101. cgoto clang 0, gcc 4개 변형 0/404(tail call 포함), switch 0(간접 점프 없음). 분포는 깔끔한 이분(간접 예측 실패 0~1.5M 아니면 65~80M), 붕괴 시 사이클 +27~31%.
  - 구조: clang은 jeven의 두 갈래를 `br` 하나로 합치는데, 홀수 갈래는 `tbnz`가, 짝수 갈래는 `b`가 각각 한 번씩 점프해 그 `br`에 닿는다(두 경로 모두 점프 1회). gcc musttail은 갈래마다 `br`이 따로 있고(목적지 고정), gcc musttail_args는 한쪽 갈래만 점프한다(`tbnz`로 건너뛰기).
  - **규칙**: 경로 기록 footprint(pc, target) = ((pc ≫ 1) ⊕ target)의 2~11번 비트가 jeven의 `tbnz`와 `b`에서 같으면 붕괴한다. 두 경로의 전역 이력이 같아져 `br`이 홀짝을 구분하지 못하는 것이다. 동치인 쉬운 표현: "두 분기를 함께 담는 가장 작은 정렬 블록이, 두 목적지를 함께 담는 블록의 정확히 2배"(16B/8B 51건, 32B/16B 8건, 64B/32B 5건, 그 밖의 조합 0/138).
  - 학습 데이터(seed 0~100): 202/202 일치. 무작위로 섞은 라벨로는 모순이 최소 10개(2,000번 중 0개인 경우 없음, p < 0.0005).
  - **사전 예측 검증**(seed 101~200, 측정 전에 예측을 파일로 저장, sha256 `7c03624a…`): musttail clang 33/33, musttail_args clang 31/31 맞힘, **200/200 일치, 오탐 0, 누락 0** (`a76_collapse_prediction_101-200.txt`, `layoutdist_cortex-a76_validation.txt`).
  - gcc가 붕괴하지 않는 이유도 같은 규칙으로 설명된다: gcc musttail은 이력이 필요 없는 고정 목적지 점프이고, gcc musttail_args는 두 경로의 점프 개수가 달라(1 대 0) 이력이 겹칠 수 없다.
  - 의미: (1) 배치 붕괴가 "운"이 아니라 컴파일러가 낸 블록 배치 × 예측기 해시의 결정적 결과임을 처음으로 사전 예측까지 보였다. (2) "어느 방식이 안전한가"의 답이 CPU마다 다르다: A76에서는 clang tail call만 위험, x86에서는 clang 전반, Oryon에서는 간접 붕괴 없음. (3) 완화책이 구체적이다: 합쳐진 디스패치 앞의 두 경로가 점프 개수까지 같은 모양이 되지 않게 하거나(gcc식 건너뛰기), 디스패치를 갈래마다 복제하면 된다.
  - **컴파일러 쪽 원인과 수정**(2026-11-24): LLVM의 꼬리 복제(`TailDuplicator::shouldTailDuplicate`)는 간접 분기(`isIndirectBranch`)로 끝나는 블록에 큰 한도(`tail-dup-indirect-size`)를 주지만, 간접 tail call(`TCRETURNri`, AArch64·x86 모두 `isCall`/`isReturn`, 간접 분기 표시 없음)은 대상이 아니다. 레지스터 할당 전에는 리턴·호출이라 거부되고, 배치 단계에서는 일반 한도(AArch64 `getTailDuplicateSize`: -O3 6, 그 밖 2)만 적용 → -O1/-O2는 합친 모양, -O3는 복제(LLVM main 39391d9b1d83에서 확인). `-mllvm -tail-dup-size=4`로 복제하게 하면 A76 배치 202개에서 **붕괴 0**(기본 64), 사이클 중앙값도 정상 배치 대비 −10.7%/−11.4%, 최악 −25%/−29%, 명령어 −1% (`layoutdist_cortex-a76_taildup4.txt`).
  - **LLVM 패치 준비**(2026-11-24, `docs/llvm-pr/`: `taildup-indirect-tail-call.patch`, `pr-description.md`; 기준 llvm-project main 568ec24bf925): 레지스터 할당 뒤, 다른 호출 없이 간접 tail call로 끝나는 블록의 복제 한도를 computed goto 규칙처럼 올림(새 옵션 `tail-dup-indirect-tail-call-size`, 기본 10, optsize 제외). 새 lit 테스트 AArch64·X86, `check-llvm-codegen` 전 타깃 통과(기존 테스트 변경 0; 처음 판은 swift async 테스트 1개를 바꿔 "다른 호출이 있는 블록 제외"를 추가). 같은 llc 빌드로 규칙 켬/끔 A76 배치 101개: musttail 37→0, musttail_args 32→0 붕괴, 사이클 중앙값 −12.7~−12.8%, 최악 −28~−30% (`results/analysis/layoutdist_cortex-a76_llcpatch.txt`). 이슈 재현 코드 `collapse.c` PAD 0~15(clang 21 비트코드 → 패치 llc, 2026-11-25): 규칙 끔 6/16 붕괴(clang 21 기본과 주소·판정 동일), 규칙 켬 0/16, 사이클 중앙값 6.53→5.81G(−11%), 최악 8.45→6.01G(−29%), 붕괴 안 한 배치보다도 빠름 (`results/analysis/a76_repro_llcpatch.txt`). 코드 크기(x86-64): CPython ceval +2.1%(디스패치 261→336), WAMR +0.6~1.2%, Lua 0. PR 등록은 사용자(이슈 번호 연결, 이메일 공개 주의). **LLVM 이슈 등록: [#245601](https://github.com/llvm/llvm-project/issues/245601)**(2026-11-24). **PR: [#245624](https://github.com/llvm/llvm-project/pull/245624)**(2026-11-24, 라벨 backend:AArch64·backend:X86·llvm:codegen 자동 부착). 커밋 메시지 `docs/llvm-pr/commit-message.txt`(LLVM AI 정책에 따라 `Assisted-by` 표기).
  - 최소 재현 예제 `repro/a76-tailcall-collapse/`(VM 67줄 + jeven 앞 nop 수 PAD + `-falign-functions=256`): PAD 0~15 중 6개 붕괴, 규칙 예측 16/16 일치, 두 번 실행해도 같음; `-tail-dup-size=4`는 16/16 정상 (`results/analysis/a76_repro_run.txt`). LLVM 이슈 초안 `docs/llvm-issue-draft.md`(등록은 사용자 결정, 이중 맹검 시점 고려).
  - 실제 인터프리터의 정적 점검(파이의 AArch64 바이너리 역어셈블, "두 경로 모두 점프한 뒤 합쳐지는 간접 점프" 판정; 마이크로로 검증: clang -O2 2곳, -O3 0곳, gcc 0곳): Lua tail clang 200개 중 8개(GETTABLE, NEWTABLE 등), WAMR tail clang 342개 중 5개(SELECT 등). 이 핸들러들은 다음 명령이 경로와 무관해 해가 없을 가능성이 크고, 비교·조건 점프 핸들러(EQ, LT, TEST, JMP)는 clang에서도 안전한 모양(한쪽이 흘러내려옴). → 지금 빌드된 Lua·WAMR이 이 붕괴에 걸릴 가능성은 낮다. 위험은 "배치 운"에 달려 있다는 것이 요점. CPython은 ⬜ 미점검.
  - **경로 길이 실험**(`repro/a76-path-length/`, `results/analysis/layoutdist_cortex-a76_pathlen.txt`): jeven의 한쪽 갈래에 무조건 점프(`b 1f; 1:`)를 하나 넣어 두 경로가 점프를 1번과 2번 거치게 하면, 같은 조건(clang 21 -O2, 배치 101개 × 2변형)에서 **붕괴 0/202**(원래 1번 대 1번은 35/101, Fisher p = 1.9×10⁻¹⁹). → A76 붕괴는 "두 경로의 분기 이력이 길이까지 같고 해시만 다른" 경우에 한정된다(규칙과 맞음).
    - **2 대 2**(양쪽 갈래에 서로 다른 문자열의 무조건 점프를 하나씩: 같은 문자열이면 clang이 갈림길 앞으로 끌어올려 1 대 1이 됨, `musttail_extra_both.c`, `layoutdist_cortex-a76_pathlen2.txt`): **0/101**(1 대 1은 35/101). → 길이가 같아도 이력이 두 칸에서 다르면 겹치지 않는다. 붕괴 조건은 "두 경로의 이력이 마지막 점프 하나만 다르고, 그 하나의 해시가 같음"으로 좁혀진다. 한 가지 모양 계열의 결과라 "불가능"까지는 아님.
  - **CPython 3.15 점검**(clang 21, `--with-tail-call-interp`, `ceval.o`만 컴파일, `analysis/dispatch_join_scan.py`, `results/analysis/dispatch_join_scan_a76.txt`): 위험 후보 합류가 **-O3(기본)에서도 62곳**(-O2도 62곳). 디스패치 꼬리가 길어 -O3 한도(6)로도 복제되지 않는다. 그러나 대표 사례를 보면 FOR_ITER_LIST는 반복 종료/계속 디스패치가 이미 갈래마다 따로 있고(후보는 incref 분기라 대상 불변), POP_JUMP_IF_NONE은 점프/비점프 두 경로가 하나의 디스패치로 합쳐지지만 경로의 점프 수가 1 대 2 이상 → 위 실험상 붕괴하지 않는 모양. → CPython이 이 특정 붕괴에 걸릴 근거는 찾지 못함(62곳 전부를 본 것은 아님). 실측은 ⬜.
    - **3.14.0**(tail call 인터프리터가 처음 들어간 릴리스, python.org 소스 MD5 확인): 위험 후보 -O3 54곳, -O2 53곳으로 3.15와 비슷. POP_JUMP_IF_NONE은 3.15와 같은 1 대 2+ 모양. FOR_ITER_TUPLE은 계속/종료 두 경로가 디스패치 하나로 합쳐지고, 경로의 점프 수가 원소에 따라 1~2(계속)와 2(종료)라 **2 대 2로 길이가 같아질 수 있다** → 2 대 2 실험(0/101, 위)상 붕괴하지 않는 모양. 게다가 종료는 루프당 1회라 겹쳐도 영향이 작다. → CPython 3.14.0·3.15에서 이 붕괴의 근거는 찾지 못함.
  - 기존 보고 검색(2026-11-24): 간접 tail call의 꼬리 복제 문제나 A76의 배치 의존 간접 예측 붕괴를 다룬 보고는 찾지 못함. 같은 계열의 선례는 computed goto 쪽(#106846, PR #114990: clang 19 회귀를 2025-03에 수정, 논의에 tail call 언급 없음)과 Elhage의 CPython 분석.
  - x86·Oryon에는 이 규칙을 적용할 수 없다(해시가 다르고, x86 붕괴는 고정 목적지 점프 두 개의 충돌이라 형태도 다름). 덧붙여 A76 정상 배치의 절반쯤에 약 1.5M의 약한 간접 예측 실패 층이 따로 있다(성능 영향 작음, 미분석).
- 6.2b 21개 배치, 10개 변형, -O2/-O3(i5): 아래는 초기 결과(6.2a로 대체됨).
- 6.2 분포: 방식 × 컴파일러 × 최적화 단계마다 원래 배치 1개 + 무작위 배치 20개(i5). ✅ (414/420)
  - 방법: 실행 흐름이 이어지지 않는 코드 레이블 앞에 실행되지 않는 0~63바이트 빈 공간을 무작위로 넣는다(`analysis/perturb.py`). ~~실행 명령어 수는 배치끼리 1,000개 미만 차이 → 주소만 바뀐다.~~ **정정(2026-11-23)**: 6변형에서만 맞다. cgoto clang, musttail gcc, musttail no-pie gcc, musttail_args gcc는 명령어 수가 배치마다 49~79% 달랐다 — 같은 주소의 연속 레이블(clang `.LtmpN:` 다음 `.LBB0_k:`, gcc `f:` 다음 `.LFBn:`) 사이에도 패딩이 들어가 디스패치마다 실행됐기 때문(perturb.py 버그, 8절). 이 4개 변형의 6.2b 수치(변동 폭 등)는 쓰지 않는다. 6.2a에서 고친 모드로 재측정.
  - **간접 점프 예측 붕괴**(간접 예측 실패 > 10M; 정상 1~4M, 붕괴 3~4억): 무작위 배치의 일부에서 발생하고, 발생하면 사이클 +30~50%.

    | 방식 | 붕괴 / 배치 | gcc | clang |
    |---|---|---|---|
    | **cgoto** | **0 / 84** | 0 | 0 |
    | switch | 2 / 84 | 0 | 2 |
    | musttail no-pie | 1 / 84 (경계) | 0 | 1 |
    | musttail | 3 / 84 | 0 | 3 |
    | musttail_args | 6 / 78 | 2 | 4 |

  - 붕괴는 tail call만의 문제가 아니다: clang switch(핸들러마다 점프를 복제한 구조)에서도 생긴다. clang 코드가 더 취약(clang 약 10건 대 gcc 2건).
  - cgoto는 84개 배치에서 붕괴 0건. cgoto gcc는 가장 빠르면서 가장 안정적: 중앙값 27.99G(-O2, 1위), 최선~최악 5.0%, 변동계수 1.1%. 비교: musttail clang 50.4% / 10.2%, musttail_args clang 47.2% / 12.0%, switch clang 45.3% / 9.0%.
  - 붕괴가 아닌 변동도 있다: switch gcc 15%, cgoto clang 14%, musttail gcc 12%(최선~최악).
  - 원래 배치가 대표값인가: 대부분 중앙값 ±5% 이내. 예외는 musttail clang -O3(원래 배치가 붕괴 사례, 중앙값 대비 +43%).
  - 한계: 붕괴 확률이 약 5%라면 21개에서 우연히 0건일 확률 약 34%, cgoto 84개 전체로도 약 1.3% → 시사적이지만 확정은 아님. 간접 점프 개수로는 설명 안 됨(cgoto clang과 switch clang 모두 10개인데 switch만 붕괴). 🔄 배치 100개(i5, i9) + 붕괴 사례의 주소 분석 예약됨.
  - 질문: cgoto가 tail call보다 배치에 덜 민감한가? → i5에서는 그렇다(잠정). i9와 100개 배치로 확인 중.
- 6.3 방법론적 함의: 바이너리 하나로 디스패치 방식을 비교하면 배치 우연을 방식의 차이로 오인할 수 있다(Mytkowicz 2009). 우리도 처음엔 오인했다.
- 그림: 위치 이동 실험(K별 예측 실패), 방식별 성능 분포(바이올린/상자 그림).

## 7. Discussion: When Is Computed Goto Worth It?

- 결과가 다 나오면 판단 기준표로 정리. ⬜
- 초안:
  - 이식성/MSVC가 필요 → switch(+ unreachable) 또는 tail call(MSVC 2026 실험 기능).
  - gcc 중심 → cgoto(switch는 점프 복제가 안 됨, tail은 preserve_none 레지스터가 적음).
  - clang + preserve_none 가능 → tailpn이 가장 빠를 수 있음(Lua −7.4%). 단 배치 민감도 확인 필요.
  - 디버그 빌드(-O0/-O1) 성능이 중요 → tail call.
  - ARM(넓은 코어) → tail call이 cgoto보다 3~4% 빠를 수 있다(마이크로벤치마크). switch는 비교 트리가 될 수 있어 피한다. Lua 결과로 확인 필요. 🔄
- ~~"cgoto는 쓸 가치가 있다"의 정확한 형태: 최고 속도가 아니라 컴파일러와 배치 변화에 대한 안정성. ✅ 6.2a에서 확정(cgoto 붕괴 0.7% 대 tail call 3.2%, p = 0.008).~~ **철회(2026-11-23)**: 고친 6.2a에서 cgoto 1.5% 대 tail call 2.2%, p = 0.51. 배치 안정성은 cgoto의 근거가 되지 못한다. 안정성을 가르는 건 컴파일러(gcc 0.5% 대 clang 2.8%)와, 간접 점프가 하나뿐인 구조(switch gcc 0건)다.
- 결과 종합(2026-11-23):
  - 최고 속도: 조건에 따라 다르다. clang + preserve_none(tailpn)이 i9·갤럭시 Lua, CPython(PGO)에서 1위. i5에서는 cgoto gcc가 1위. gcc에서는 세 방식이 ±1~5%.
  - 안정성(배치): 방식끼리는 구분되지 않는다(cgoto 1.5% 대 tail call 2.2%, p = 0.51). 컴파일러가 가른다(gcc 0.5% 대 clang 2.8%, p = 0.0003). 가장 안전한 건 점프 하나짜리 switch gcc(0건). (2026-11-23 정정)
  - PGO: 켜면 cgoto의 이점이 사라진다(CPython).
  - 큰 인터프리터: 컴파일러가 cgoto의 점프를 합친다(Lua 1~46개, 같은 소스가 컴파일러 버전에 따라 1~157개) → cgoto의 구조 보장은 약하다.
  - 그러므로 "cgoto는 쓸 가치가 있다"의 정당한 형태는: **PGO 없이 gcc로 빌드하는 인터프리터에서, CPU가 바뀌어도 크게 흔들리지 않는 무난한 선택**(i5 1위, i9에서도 최고와 5~6% 안). 배치 안정성은 근거가 아니다. 최고 속도가 목표면 clang + preserve_none tail call, 이식성이 목표면 switch. gcc + cgoto라면 `-fno-crossjumping`(i9 −4.7%, i5 −2.4%).
- **주장 수정 필요(2026-11-23)**: "cgoto는 디스패치 구조를 프로그래머가 보장한다"는 큰 인터프리터에서 틀렸다. 컴파일러가 cgoto의 점프를 1~46개로 합친다(Lua, 5.3). 구조 보장은 tail call의 장점이다. 따라서:
  - ~~cgoto의 안정성 주장은 "점프가 실제로 핸들러마다 남아 있는 경우(작은 인터프리터)"로 범위를 좁힌다.~~ 배치 안정성 주장 자체를 철회(6.2a 정정).
  - tail call(특히 tailpn)의 장점: 구조 보장 + clang에서 최고 속도(Lua i9 −3.2%, 갤럭시 −6.0%). 단점: preserve_none 의존, gcc 지원 약함. 배치 붕괴는 cgoto와 같은 수준(6.2a), clang 코드에서 더 잦다.
  - ARM(Oryon): Lua에서 tailpn이 모든 벤치마크에서 cgoto보다 빠르다 → ARM + clang이면 tailpn 권장.

## 8. Threats to Validity

- CPU 다양성: 인텔 두 종 + ARM 둘(Oryon, Cortex-A76). AMD가 없다 → 협력자 측정 예정. ⬜ 서버 ARM은 N1의 바탕 코어인 A76으로 일부 대신한다(같은 코어 설계지만 캐시·메모리 계층과 클럭이 다름). 파이 5는 공용 장비라 다른 사용자의 부하가 섞일 수 있다(실행마다 load average 기록).
- 갤럭시 측정의 한계: 클럭 고정 불가(발열로 평균 3.7~4.2GHz, 쿨다운 전엔 2.5GHz까지) → 시간이 아니라 사이클로 비교. 그래도 사이클 편차는 0.0~0.1%로 매우 작았다. 안드로이드 백그라운드 부하(load average 약 10). clang만 비교 가능. WAMR, CPython 제외.
  - 배치 실험(6.2c)은 도중에 충전을 시작했다(배터리 44% → 33%에서 충전기 연결). 실행 순서가 무작위이고 실행마다 46°C 이하로 식힌 뒤 재므로 변형 사이 비교는 치우치지 않는다. 붕괴 판정(예측 실패 수)은 클럭과 무관하다.
  - 간접 예측 실패 이벤트 0x8117은 공개 문서가 아니라 탐침으로 확인한 것이다(정의된 이름 없음). 탐침의 세 모드에서 기대한 대로 움직이는 것만 근거다.
- 마이크로벤치마크의 특수성(코드와 데이터가 같은 배열, 핸들러 7개).
- 실제 인터프리터의 tail call 변환은 우리가 만든 것(CPython 제외) → 더 나은 수작업 변환이 가능할 수 있음.
- CPython 기본 측정은 PGO 없음 → PGO+LTO 측정으로 보완. ✅
- pyperformance가 측정 중 일부 패키지를 설치(전체 perf 카운터에만 영향). genshi 벤치마크는 3.15에서 실패해 제외.
- Lua의 해시 시드/ASLR로 인한 변동 → 고정 후 재측정(편차 중앙값 3.5% → 0.6%). ✅
- 배치 섭동 도구의 버그(2026-11-23 발견·수정): `perturb.py`가 같은 주소를 공유하는 연속 레이블의 뒤쪽 레이블 앞에도 패딩을 넣어, 앞쪽 레이블로 점프할 때마다 패딩이 실행됐다(cgoto clang, musttail/musttail_args gcc; 명령어 수 +49~80%). 발견 경로: 같은 소스의 배치끼리 명령어 수가 달랐다. 수정: 연속 레이블에서는 첫 레이블 앞에만 패딩(`mode fixed`, 기본값). 예전 동작은 `mode orig`로 바이트 단위 재현(224건 확인). 나머지 5개 변형은 두 모드의 출력이 같아 기존 데이터가 유효하고, 문제 변형 3개는 i5·i9에서 101개 배치를 재측정(6.2a). 검증 기준을 요약 스크립트에 넣었다: 배치끼리 실행 명령어 수가 같아야 한다(`analysis/layoutdist_summary.py`의 "instr const").
- **WAMR c-ray는 빈 장면을 렌더링했다**(2026-11-23 발견, 파이 5 준비 중): c-ray는 장면을 표준 입력으로 받는데 `targets/wamr/run.sh`가 넘기지 않았다. x86 WAMR 결과 파일 4개(i5·i9 × -O2·-O3) 모두 c-ray 명령어 수가 8.9~9.5G로, 빈 입력(9.46G)과 같고 장면 파일(71.1G)의 7분의 1이다. 모든 변형이 같은 입력이었으므로 변형 간 비교는 공정하지만, 의도한 작업은 아니다.
  - **i9 재측정**(2026-11-24, `analysis/wamr_cray_scene.sh`: 빈 장면과 장면을 같은 세션에서 -O3·-O2 각 5회, `results/wamr{,-O2}-cray_i9-14900k_raw.txt`, 비교 `analysis/wamr_cray_compare.py`): 같은 세션의 빈 장면 값이 기존 값을 재현(cgoto clang −6.1% 대 −6.3%). c-ray 하나만 보면 장면에 따라 크게 달라진다(-O3 cgoto clang −6.1% → **+3.9%**, tailpn gcc −4.9% → −1.3%). 그러나 8개 프로그램 기하평균은 최대 1.2%p만 움직이고(-O3 cgoto clang −5.8% → −4.6%), 벤치마크 부트스트랩 구간의 유의/비유의 판정은 -O3·-O2 모두 그대로다. → 본문은 장면 버전 수치로 바꾸고 이 경위를 각주로 적는다. ⬜ i5 재측정(데스크톱 앱 종료 필요). 파이 5에서는 둘 다 잰다(`cray` = 빈 입력, x86과 비교용; `crayscene` = 장면). 발견 경로: 파이 5의 사전 검사 루프에서 c-ray가 루프의 입력 목록을 장면으로 읽어 들여 뒤 항목이 사라졌다 → 측정 도구(`bench/android_run.sh`)도 명령의 표준 입력을 /dev/null로 막도록 고침.
- 측정 위생: 오염된 i5 데이터를 두 번 폐기하고 재측정했다. (1) 같은 기계에서 빌드/테스트를 함께 돌려 마이크로벤치마크 편차가 1.4~25%로 커짐. (2) 데스크톱 앱(Chrome, Vesktop) 부하로 Lua -O2 편차 중앙값 9%(재측정 후 0.83%). 이후 측정 중에는 무거운 앱을 종료.

## 9. Related Work

- `docs/related-work.md` 참고. 핵심: Bell 1973, Ertl & Gregg 2003(JILP, PLDI/TOPLAS), Berndl 2005, Shi 2005, Rohou 2015, Seznec ITTAGE, Haberman 2021, Elhage 2025, Ken Jin 2025, Deegen 2024, Titzer 2022, Mytkowicz 2009.
- ⬜ Rohou 2015 이후 인용 논문 조사, AMD/ARM 디스패치 비교 연구 존재 여부 확인.

## 10. Conclusion

- 분기 예측 → 컴파일러 코드 생성과 배치로 관심을 옮겨야 한다.
- cgoto의 가치: gcc에서 CPU가 바뀌어도 무난한 속도(배치 안정성은 방식이 아니라 컴파일러의 성질). tail call의 가능성: 조건이 맞을 때(clang + preserve_none) 최고 속도.

---

## 그림과 표 목록 (초안)

| # | 내용 | 데이터 | 상태 |
|---|---|---|---|
| F1 | 세 방식의 디스패치 코드(어셈블리) | `objdump` | ✅ |
| T1 | 마이크로벤치마크: 방식 × 컴파일러 × -O2, 사이클/명령어/예측 실패 | `results/i9-14900k_O2_summary.csv` | ✅ |
| F2 | 예측 실패 분해(조건/간접) | `results/analysis/misp_split_*.txt` | ✅ i5 / ⬜ i9 |
| F3 | 최적화 단계별 사이클(-O0~-O3) | `results/*_O*_summary.csv` | ✅ |
| T2 | tail call 변환 규모와 검증 | 변환 로그, 테스트 결과 | ✅ |
| F4 | 실제 인터프리터 기하평균(Lua, WAMR, CPython) | `results/lua_*`, `wamr_*`, `cpython*_*` | ✅/🔄 |
| F5 | 벤치마크별 분포 | 같은 데이터 | ✅/🔄 |
| F6 | 위치 이동 실험(K별 예측 실패) | `results/analysis/sweep_*.txt` | ✅ i5 |
| F7 | 방식별 배치 민감도 분포(상자 그림 + 붕괴 표시) | `results/analysis/layout_*.txt`, `layoutdist_*.txt` | ✅ |
| T5 | 방식 × 컴파일러별 붕괴 횟수(i5, i9, 갤럭시) | `results/analysis/layoutdist_summary.txt`(fixed 재측정·갤럭시 반영; 예전 값은 `_orig.txt`) | ✅ |
| F11 | 갤럭시 musttail clang: 배치별 사이클(이분 분포) + 느린 배치의 정체 분해 | `layoutdist_galaxy-s25edge.txt`, `layoutdiag_galaxy-s25edge_summary.txt` | ✅ |
| F12 | A76 붕괴 규칙: 분기 쌍 블록 × 목적지 쌍 블록 표, 사전 예측 200/200 | `a76_collapse_rule.txt`, `layoutdist_cortex-a76{,_validation}.txt` | ✅ |
| F13 | 같은 명령어 흐름(clang 21 AArch64)의 코어 폭 비교: Oryon 대 A76 | `micro_galaxy-s25edge_raw.txt`, `cortex-a76_O3_raw.txt` | ✅ |
| F9 | 붕괴 사례에서 충돌하는 간접 점프의 주소 관계 | `results/analysis/catastrophe_*.txt` | ✅ |
| T3 | 판단 기준표 | 종합 | ⬜ |
| T4 | ARM(Oryon) 마이크로벤치마크: 사이클/명령어/IPC/예측 실패/간접 분기 수 | `results/micro_galaxy-s25edge_raw.txt` | ✅ |
| F8 | 같은 clang의 switch 코드: x86(점프 테이블 + 복제) 대 AArch64(비교 트리) | `objdump` | ✅ |
| T6 | 디스패치 루프의 간접 점프 수: 인터프리터 × 방식 × 컴파일러 × 아키텍처 | `objdump` | ✅ |
| F10 | Lua: i9 대 갤럭시, 벤치마크별 cgoto clang 대비 | `results/lua_i9-14900k_seedfix_raw.txt`, `lua_galaxy-s25edge_raw.txt` | ✅ |

## 남은 일 (우선순위)

완료:
- ✅ 예약했던 측정 전부(2026-11-23), i5 Lua -O2 재측정.
- ✅ 배치 민감도 100개 + 붕괴 원인 분석(i5, i9). 2026-11-23 섭동 도구 버그 수정 → 영향받은 3개 변형 재측정 → C4 결론 정정(방식이 아니라 컴파일러가 가른다, 6.2a).
- ✅(일부) clang 코드가 배치 붕괴에 더 취약한 이유: 디스패치 구조도, 충돌하는 두 점프의 주소 규칙도 아니다(배치 1,515개 재생성 후 전수 탐색, 6.2a). 끝까지 가려면 예측기 해시 역공학이 필요하다 → 한계로 기술.
- ✅ 세 인터프리터의 디스패치 간접 점프 수(PGO 유무 포함, 5.3 표).

A. 주장을 확정하는 실험
1. ✅ Lua 디스패치 병합 실험: 원인 ✅, i9 성능 ✅(gcc −4.7%, 이득은 예측이 아니라 프런트엔드, 5.3), i5 성능 ✅(gcc −2.4%), ARM 점프 수 ✅(EABI 툴체인 + Compiler Explorer, clang 21 AArch64는 꼬리 병합이 아니라 복제 한도 때문에 1개), clang이 CPython을 덜 합치는 이유 ✅(핸들러 끝이 제각각, 5.3).
2. ✅ 메커니즘(top-down): i9 ✅(gcc 병합 손해 = 프런트엔드, tailpn 우위 = 세 병목 고르게, preserve_none = 명령어 −15%, -O1 = gcc 미복제로 프런트엔드, 5.3/5.4). i5 ✅(CPU마다 1위가 바뀌는 이유 = 코어 폭 대비 프런트엔드 손실; i5는 명령어 수가 그대로 사이클로 감. Tiger Lake L2는 멀티플렉싱으로 틀어져 재계산). ✅ -O0: 의존 사슬 가설은 지연 주입으로 반박. 실제 차이는 같은 uop 수를 낮은 병렬성으로 실행하는 것(메모리 순서 clear 31배). 근본 원인은 가설로 남김(5.4).
3. ✅ 컴파일러 버전별 디스패치 점프 수: gcc 4.4~16, clang 3.5~23, x86-64와 AArch64(5.3 표). clang 12~21은 1개, 원인은 `tail-dup-indirect-size` 한도. ⬜ 선택: CPython/WAMR도 같은 버전 축(헤더가 많아 Compiler Explorer로는 번거로움).
4. ✅ ARM(갤럭시) 배치 실험(6.2c): 간접 점프 붕괴 0/404 → x86 붕괴는 인텔 예측기 고유. 대신 musttail clang 9/101에서 프런트엔드 정체로 2배가 되는 다른 형태의 붕괴. Oryon 간접 예측 실패 이벤트(raw 0x8117)를 탐침으로 찾음.

B. 검증과 통계
5. ✅ 통계: 부트스트랩 신뢰구간(`results/analysis/ci_all.txt`). 결과로 고친 주장은 5.3에 표시. 배치 실험의 Fisher 검정은 6.2a.
6. ✅ WAMR 공식 스펙 테스트: 8개 변형 모두 85/85 통과(4.4).
7. ✅ 5.4 실제 인터프리터 -O2 대 -O3 정리. ✅ 벤치마크별 편차 원인 = 명령어 증가량 × 기준의 프런트엔드 여유(5.3).

C. 외부
8. 🔄 AMD/서버 ARM 협력자 측정(`bench/PROTOCOL.md`). ✅ 라즈베리 파이 5(Cortex-A76, Neoverse N1의 바탕 코어): 마이크로 -O0~-O3, 배치 101개 × 8변형 + 사전 예측 검증 200개, Lua, WAMR(2026-11-24 완료; hashset은 검사 정규식 실수로 1차에서 빠져 따로 5회 재측정). ⬜ AMD는 아직 없음.
9. 🔄 선행 연구: Mytkowicz 2009, Casey/Ertl/Gregg 2007, Piumarta 1998 서지 확인 ✅, Rohou 2015 인용 논문 32건 조사 ✅(직접 관련: Zheng & Sasaki CAL 2026, Ertl & Paysan ECOOP 2024, Interpretizer 2019), LLVM 꼬리 복제 이력 ✅(`docs/related-work.md` 8~9절). ⬜ Rohou 2015 **본문**은 HAL/core.ac.uk가 자동 접근을 막아 못 읽음 → PDF를 직접 받아야 함.

D. 집필
10. ⬜ 대상 학회 결정(쪽수, 마감) → 그림 생성 스크립트, 본문 초안, 아티팩트 패키지. 후보(2026-11-23 조사, 결정은 사용자):
    - ISPASS 2027(뉴욕, 5월): 초록 2026-12-11, 본문 12-18 AoE. 성능 분석 학회라 측정 연구에 맞지만 4주 남음. ([CFP](https://ispass.org/2027/cfp/))
    - **ECOOP 2027 2라운드**: 2027-02-11, 통지 4-08, 학회 6/28~7/2 토리노. Ertl & Paysan(2024)이 같은 주제로 실린 곳. 시간 여유와 주제 적합성 모두 괜찮음 → 추천. ([일정](https://2027.ecoop.org/dates))
    - OOPSLA 2027 2라운드: 2027-04-07 AoE. ([트랙](https://2027.splashcon.org/track/splashoopsla2027))
    - CGO: 2027은 마감 지남(2026-06-11, 09-10, 11쪽). "CGO 2015 재검증"이라는 구도엔 가장 어울리지만 다음은 CGO 2028(1라운드가 2027년 6월쯤일 것으로 추정). ([CGO 2027](https://2027.cgo.org/track/cgo-2027-papers))
    - 그 밖: MPLR, VMIL(여름 마감), TACO / Programming 저널(상시).
