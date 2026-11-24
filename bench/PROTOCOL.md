# 측정 프로토콜

다른 CPU(AMD, ARM 등)에서 측정을 부탁드릴 때 드리는 문서입니다.
측정 스크립트는 각자 플랫폼에 맞게 직접 만들어 주시면 됩니다.
다만 결과를 한데 모아 비교해야 하니, 아래 **측정 조건**과 **결과 형식**은 꼭 지켜 주세요.

참고 구현: [run.sh](run.sh) (인텔 + 리눅스용), 전체 측정을 한 번에 돌리는 [all.sh](all.sh)

## 1. 준비물

- 이 저장소의 `src/`와 `bench/build.sh` (소스는 수정하지 말아 주세요)
- gcc 15 이상 (`musttail` 지원이 15부터라서 필요합니다)
- clang (있으면 같이 측정, 없으면 gcc만)
- 리눅스라면 `perf`와 코어 고정 도구(`taskset` 등)

## 2. 빌드

```sh
for o in O0 O1 O2 O3; do OPT=-$o bench/build.sh build/$o; done
```

최적화 단계마다 10개 바이너리가 나옵니다.

| 변형 | 소스 | 설명 |
|---|---|---|
| `switch` | `src/switch.c` | switch 디스패치 (`default: __builtin_unreachable()`로 범위 검사 제거) |
| `cgoto` | `src/cgoto.c` | computed goto |
| `musttail` | `src/musttail.c` | 핸들러 함수 + `musttail` |
| `mtargs` | `src/musttail_args.c` | musttail + 상태를 함수 인자로 전달 |
| `mtnopie` | `src/musttail.c` | musttail + `-fno-pie -no-pie` |

각각 `_gcc`, `_clang` 두 가지가 있습니다.
빌드가 안 되는 변형(예: macOS에서 `-no-pie`)이 있으면 빼고 측정하고, 결과를 보낼 때 알려 주세요.

**정확성 확인**: 모든 바이너리가 `1552724831`을 출력해야 합니다. 다른 값이 나오면 그 변형은 측정하지 말고 알려 주세요.

## 3. 측정 조건

| 항목 | 규칙 |
|---|---|
| 클럭 | 터보/부스트를 끄고 고정. 인텔 `intel_pstate/no_turbo=1`, AMD `cpufreq/boost=0`, governor `performance`. 고정할 수 없으면 그대로 두고 그 사실을 기록 |
| 코어 | 코어 하나에 고정. 하이브리드 CPU는 P코어(big 코어)에. 가능하면 SMT 형제 코어도 비워 두기 |
| 시스템 | 다른 무거운 작업이 없는 상태 |
| 반복 | 최적화 단계마다 10개 변형 × **5회** |
| 순서 | 회차마다 변형 순서를 **무작위로 섞기** |
| 쿨다운 | 실행 사이에 **최소 3초**. 온도를 읽을 수 있으면 일정 온도 아래로 내려갈 때까지 대기 |
| 카운터 | 가능하면 `cycles`, `instructions`, `branches`, `branch-misses` (사용자 모드) |

## 4. 결과 형식

### 원본 파일 (raw)

한 실행에 한 줄, 공백으로 구분한 11개 열입니다.
이 형식을 지키면 [to_csv.sh](to_csv.sh)로 바로 CSV를 만들 수 있습니다.

```
round variant time_s cycles instructions branches branch_misses ghz temp_before temp_after loadavg
```

| 열 | 뜻 | 예 |
|---|---|---|
| `round` | 회차 (1~5) | `1` |
| `variant` | 변형 이름 | `cgoto_gcc` |
| `time_s` | 실제 경과 시간(초) | `11.358438590` |
| `cycles` | 사용자 모드 사이클 수 | `27206910836` |
| `instructions` | 사용자 모드 명령어 수 | `35925593921` |
| `branches` | 분기 수 | `7810051928` |
| `branch_misses` | 분기 예측 실패 수 | `193940717` |
| `ghz` | 평균 클럭 = cycles ÷ (task-clock 초 × 10⁹) | `2.396` |
| `temp_before` | 실행 전 CPU 온도(°C, 정수) | `41` |
| `temp_after` | 실행 후 CPU 온도(°C, 정수) | `43` |
| `loadavg` | 실행 직후 1분 load average | `0.53` |

잴 수 없는 값은 `NA`로 채워 주세요(예: macOS에서 perf 카운터).

### 파일 이름

```
<cpu모델>_<최적화단계>_raw.txt
```

CPU 모델은 소문자와 하이픈으로 씁니다. 예: `ryzen9-7950x_O2_raw.txt`, `graviton3_O0_raw.txt`, `apple-m2_O3_raw.txt`

### 환경 정보 파일

`<cpu모델>_env.txt`에 아래 내용을 적어 주세요.

- CPU 모델명, 코어 구성(하이브리드 여부)
- OS와 커널 버전
- gcc, clang, perf 버전
- 터보/부스트 상태, governor, 측정 중 클럭
- 측정에 쓴 코어 번호, SMT 형제 코어 사용 여부
- 측정에 쓴 스크립트 (파일 그대로 첨부해 주시면 가장 좋습니다)
- 지킬 수 없었던 조건과 그 이유

## 5. 보내 주실 것

- 최적화 단계별 원본 파일 4개 (`_O0_` ~ `_O3_`)
- 환경 정보 파일 1개
- 측정 스크립트
