# Передача microcpu / HC1200 / J11 следующей сессии

Состояние на **2026-08-29**. Это инструкция для продолжения работы, а не
запрос заново реализовать уже готовые функции. Сначала прочитай этот файл,
проверь актуальный `git status` и последнее задание пользователя. Если нового
задания нет, уточни следующий шаг; не начинай автоматически ODT, MMU или FP11.

## 1. Где находится проект

| Назначение | Путь / адрес |
|---|---|
| Основной репозиторий на Mac | `/Users/sash/Work/FPGA/microcpu` |
| Рабочая ветка | `fpga-j11` |
| C-эмулятор, эталонные core-тесты, microasm11 | `/Users/sash/Work/PROJECTS/k1801vm1` |
| Образ RT-11 | `/Users/sash/Work/PROJECTS/k1801vm1/lsi11/disks/rt11v503.dsk` |
| Ubuntu для Diamond и программирования | `ssh sashz-ubuntu`, запасной адрес `192.168.1.108` |
| Репозиторий на Ubuntu | `/home/sash/Work/FPGA/microcpu` |
| Diamond | `/home/sash/.local/lscc/diamond/3.14` |
| Отдельный Programmer | `/home/sash/.local/lscc/programmer/diamond/3.14` |

Сессия приложения может открыться в `k1801vm1`, но изменять надо **microcpu**.
Явно задавай рабочую директорию; не правь соседний C-core вместо FPGA-проекта.
При ограничениях sandbox запрашивай разрешение на запись вне workspace.
Не обходи ограничения другими способами.

Перед этой передачей HEAD документации был `47f2487`; предыдущий коммит
документации — `078aafd`. Этот файл будет в следующем коммите: актуальный HEAD
узнавай через `git log`, не подставляй хеш документации вместо хеша прошивки.
В начале передачи tracked-изменений не было. В дереве есть пользовательские
untracked-файлы: `AGENTS.md`, `.DS_Store`, инструменты/объекты сборки,
`asm/microasm.c-`, `asm/microasm.c.orig`, результаты тестов и старые MEM.
Не удаляй их, не делай `git clean`, reset/checkout и не добавляй всё через `git add .`.

На Ubuntu ранее была несвязанная пользовательская правка
`boards/hc1200-microcomp/j11.sty`, а HEAD отставал от Mac. Поэтому Diamond
запускали в **чистом отдельном git archive**, не перезаписывая Ubuntu checkout.
Это историческое наблюдение: перед новой работой проверь состояние заново.

## 2. Что пользователь принципиально потребовал

- J-11 эмулируется **ассемблерным микрокодом** на небольшом RISC-движке.
  Декодирование PDP-11, EA, PSW, банки регистров/SP, HALT, CPU-регистры,
  DL11, таймер и RK611 должны оставаться в ASM, не переезжать в J11-specific RTL.
- В Verilog допустимы общие механизмы: RISC, RAM, SPI FRAM, SPI byte service,
  raw UART и независимый счётчик времени/уведомления событий.
- Исходники микрокода писать на ASM и компилировать `microasm`, а не править
  HEX/MEM или константы машинных слов вручную.
- Гостевые тесты писать на PDP-11 ASM, собирать **microasm11 --cpu dcj-11**.
  Нужны тесты J-11 без MMU, не весь набор VM1/VM2 из соседнего проекта.
- Сохранять исходный RISC и первый модифицированный движок/микрокод.
  Активная разработка идёт в третьем профиле `ucode`.
- Legacy остаётся **главной документацией** в README и основной странице
  microcomp; два микродвижка и их аппаратные конфигурации описаны отдельно.
  Это не меняет текущий default Makefile/LDF: он по-прежнему SD boot.
- Сгенерированные BIN/MEM/EBR/JED/логи не коммитить. Коммитить проверенные
  шаги, не включать чужие изменения. Push без отдельной просьбы не нужен.
- Основные проверки — на Mac. Diamond уже использовался с разрешения,
  но его сборка **не равна** симуляции, а экспорт JED **не равен** прошивке.
  Не заявляй успех без соответствующего лога/кода возврата/отчёта.
- Уже прошитая рабочая версия обозначена **Stable J11 / RT-11 SD boot**.
  Сохраняй её как известную рабочую базу. Не прошивай плату и не меняй
  физическую SD/FRAM, драйверы или приложения автоматически по этому документу.

## 3. Три native CPU — не перепутать

| `microasm --cpu` | RTL | Основной ASM | Статус |
|---|---|---|---|
| `original` (default ассемблера) | `rtl/cpu.v` | Старые программы и bootloader | Исходный RISC, legacy |
| `j11` | `rtl/j11_microengine.v` | `ucode/j11.asm` и соседние include | Сохранённый первый микродвижок |
| `ucode` | `rtl/ucode_cpu.v` | `ucode/v2/j11.asm` и независимые include | Специализированный активный движок |

Девять сохранённых RTL/ASM-файлов проверяются на побайтовое соответствие
`d4dabf1`: `python3 testbench/check_preserved_profiles.py`. Этот коммит должен
быть доступен в истории. Бинарники разных native ISA не взаимозаменяемы.

`ucode/v2` — версия микрокода, не четвёртый CPU. SD boot, NOFIS trace и
native diagnostics — варианты прошивки **того же `ucode`**.

Особенности `ucode`: LDI8, прямые GGET/GSET для 64 context words, CALL/JMP/RET
в одно слово, ADC/SBC и CBZ/CBNZ, внутренний 12-битный word-PC. Метки, LR и
косвенные адреса — байтовые; чтение native PC у инструкции по A даёт A+1.
Обычная native инструкция — шесть тактов; сдвиги и ожидание внешней памяти
добавляют такты. Native C после вычитания означает **borrow**; SBC = A-B-C.
CBZ/CBNZ сохраняют NZVC, диапазон -32..31 слов относительно своей инструкции.
Автоматического сокращения команд/relaxation нет; SET остаётся двумя словами.
Native MOVL/MOVH удалены из `ucode`, но гостевой MOVB полностью остаётся.
Native SUBB — внутренняя помощь с byte flags, не несуществующий PDP-11 SUBB.

Объекты: original v1, j11 v2, ucode v4; старые ucode v3 принимаются, ucode v2
отвергаются. `microlink` запрещает смешивать CPU-профили; `microdis` требует
правильный `--cpu` для raw BIN. `cpu ucode` в ASM — проверка CLI-профиля,
не переключение ISA посреди файла. Все `__CPU_*__` определены: проверять `if`,
не `ifdef`. Подробности: [CPU profiles](cpu-profiles.md).

## 4. Точная стабильная сборка, уже находящаяся на плате

| Параметр | Значение |
|---|---|
| Название | **Stable J11 / RT-11 SD boot** |
| Исходный коммит | **`a985039cbc407746ed2ad38eb44c76b28821eb7c`** |
| Проект | `boards/hc1200-microcomp/microcomp.ldf` |
| Implementation / каталог | `impl1` / `impl1-sdboot` |
| Top | **`ucode_sd_microcomp`** из `sd_microcomp.v` |
| CPU | `rtl/ucode_cpu.v`, native профиль `ucode` |
| ASM | `ucode/v2/j11.asm` + `ucode/experimental/rh11_sd.asm` |
| Defines | `J11_DISK_PROTOTYPE`, `J11_SD_AUTOBOOT`; **FIS включён** |
| FPGA | **LCMXO2-1200HC-4SG32C**, QFN32 |
| Diamond / BITGEN / TRACE | **64-bit 3.14.0.75.2** |
| Синтез | **Synplify Pro V-2023.09L-2, Build 349R**, Sep 17 2024 |
| Host / strategy | Ubuntu 24.04.4 LTS x86-64 / `Strategy1` из `j11.sty` |
| Установка Diamond | `/home/sash/.local/lscc/diamond/3.14` |
| Checksum прошитого JED | **`5C98`** |

Нормальный выход сборки:
`boards/hc1200-microcomp/impl1-sdboot/microcomp_impl1.jed`.
**Точная прошитая копия** сохранена отдельно на Mac и Ubuntu:
`boards/hc1200-microcomp/impl1-sdboot/kdj11a-a985039/microcomp_impl1.jed`.
Там же есть `.mrp/.par/.twr/.pad/.prf/.srr/.bgn`, ROM/EBR,
`diamond-build.log`, `verify-id.xcf/.log`, `program.xcf/.log`.

| Артефакт | SHA-256 |
|---|---|
| `j11_sd.mem` | `486059bae5ee65f89711de00d553445f555c0a310c3c72682eec0ea9da2abc60` |
| `sd_urom_ebr.v` | `5ce3af688c1bd734fdf08d5ef50cf120b7d31913778888fbfdf79fe34e4c62d5` |
| `microcomp_impl1.jed` | `9fe90319139a8e91b6fa19f7bc55d98b8ad327bd3af56c076815ea41b58593d3` |

Это хеши **конкретных сохранённых файлов**, а не обещание одинакового JED
при каждой сборке исходников. Другая версия Diamond/Synplify/strategy может
изменить конфигурацию, ресурсы и timing. Даже при той же версии timestamp
в JED (`Fri Aug 28 23:18:17 2026`) влияет на SHA-256 всего файла. Стабильный
JED не перезаписывать новой сборкой. Подробности: [acceptance](hc1200-sd-diamond.md).

## 5. Ресурсы, память, периферия и распиновка

Полная SD+FIS плата: **1095/1280 LUT4, 548/640 slices, 431/1346 registers,
7/7 EBR, 17 PIO + JTAGENB / 22**. Частота OSCH **26.6 MHz**. TRACE максимум
**37.627 MHz**, setup/hold errors=0, cumulative negative slack=0, unrouted=0.
Это internal timing closure, не проверенная частота разгона и не измерение
внешних SD/FRAM timing margins. В BITGEN используется CFG, UFM не задействована.

uROM/context: `ucode/config.mk`, **3584 × 16 bit**, семь явных PDPW8KC банков.
Последние **64 слова — context RAM**, лимит кода **3520 слов**. Guest registers,
банки и PSW живут в context, не в отдельном J-11 RTL register file. Только
8×16 native working registers остаются distributed RAM. Guest stack contents
лежат во внешней FRAM. Нет свободной EBR для простого увеличения uROM.

| Образ при `a985039` | Code words | Context | Свободно |
|---|---:|---:|---:|
| Stable SD + FIS + autoboot | 3501 | 64 | 19 |
| SD + autoboot без FIS | 3181 | 64 | 339 |
| NOFIS boot trace | 3443 | 64 | 77 |
| Native SD/FRAM diag | 944 | 64 | 2576 |
| `ucode` без диска, с FIS | 2826 | 64 | 694 |
| Сохранённый `j11` | 3463 | 64 | 57 |

Guest RAM — **56 KiB** (`0..0xDFFF`), физическая FRAM — **128 KiB**.
Во втором FRAM bank секторный cache: **512 bytes, 0x10000..0x101FF**.
Банки SP K/S/U и два набора R0..R5 уже реализованы. HALT/Proceed использует
private mailbox; терминального ODT ещё нет. UART — **115200 8N1 без flow
control**, 3.3 V, общий GND. Активная `ucode` плата имеет **50 Hz**
(`TICK_DIVISOR=532000`); сохранённый `j11` оставлен на ~60 Hz (`443333`).
FRAM/SD fast SCK ~6.65 MHz, SD init ~195.6 kHz.

| Сигнал FPGA | Site | QFN pin |
|---|---|---:|
| UART RX (от TX адаптера) | **PT15D** | 25 |
| UART TX (к RX адаптера) | **PT17D** | 23 |
| SD CS | PL9B | 5 |
| SD MOSI | PR5C | 21 |
| SD SCLK | PT12D | 27 |
| SD MISO | PT12C | 28 |
| FRAM CS | PB4C | 8 |
| FRAM MOSI | PB20D | 17 |
| FRAM SCLK | PB6C | 9 |
| FRAM MISO | PB6D | 10 |
| Reset | PL9A | 4 |
| JTAGENB | PT15C | 26 |

`sd.lpf` сохраняет **весь** legacy `microcomp.lpf`, заменяя только gpio0..3
на SD. Не переставлять UART и не менять pulls: RX/TX, SD, FRAM — NONE,
reset — UP, keyboard rows — DOWN. Не назначать дополнительные порты на те
же pins. `JTAG_PORT=DISABLE` оставлен сознательно; нужен правильный JTAGENB.
Предупреждения unused keyboard, configuration ports, EBR wake-up/WID и
Synplify существуют; полный отчёт не warning-free. Сверяй конкретные warnings,
не объявляй любое missing-port сообщение безвредным.

## 6. Что реализовано в гостевом J-11

Основной integer ISA, byte-команды и все согласованные EA, `XOR`, `MFPS/MTPS`,
`MFPT/SPL`, `WAIT/RESET/RTT`, **MARK**, `TSTSET/WRTLCK`, EIS
**MUL/DIV/ASH/ASHC**, FIS **FADD/FSUB/FMUL/FDIV**, traps/interrupts,
RS и SP banks, HALT/Proceed уже есть. Не начинать их заново по старым сообщениям.
Полные previous-space/split-I/D semantics не реализованы; существующие MxPI/D
работают в упрощённой unified-memory конфигурации.

В микрокоде находятся guest CPU I/O:

| Регистр / устройство | Адреса и особенности (octal) |
|---|---|
| MEMERR | `177744`, без реального parity hardware |
| CCR | `177746`, маски/семантика в ASM; физического CPU cache нет |
| MAINT | `177750`, **`000020`**, read-only module ID=1, FPA=0 |
| HITMISS | `177752`, нет истории реального cache |
| CPUERR | `177766`, sticky error semantics |
| PIRQ | `177772`, приоритеты/арбитраж в ASM |
| PSW | `177776`, маски, банки, привилегии и byte lanes в ASM |
| DL11 console | `177560..177566`, RX/TX interrupts и polling |
| KW11-L-compatible clock | `177546`, vector `100`, BR6, nominal 50 Hz |
| RK611/RH11 slot | base **`177440`**, vector **`210`**, BR5 |

**Программируемого STKLIM у J-11 нет.** Fixed kernel stack limit — **`0400`**;
yellow/red stack errors реализованы по документации, не по C-only STKLIM.
MMU в активном профиле **отсутствует**: MMR/PAR/PDR accesses дают vector 4
и CPUERR.TMO. Сохранённый `j11` всё ещё имеет старые zero/ignore MMU stubs,
поэтому он не эквивалентен стабильной RT-11 конфигурации.

Raw native service window `0xF000..0xF00C` не должен быть доступен guest.
Новые `0xF008` SPI byte, `0xF00A` CS/speed, `0xF00C` FRAM bank override —
службы микродвижка, не гостевые J-11-регистры. Native cause/IRQ/control slots
10/11/15 — service ports; остальные обычные context words — ASM-owned RAM.

## 7. RT-11, исправленные ошибки и честная трактовка вывода

Используется **тот же** образ, с которым работает соседний C-эмулятор:

```sh
cd /Users/sash/Work/PROJECTS/k1801vm1/lsi11
./lsi11 -rh disks/rt11v503.dsk -boot rh0
```

Эта команда — справка о C-эмуляторе, не необходимый этап FPGA-теста. Не
запускай её просто ради проверки пути: не предполагай для неё read-only overlay.
Размер образа **27,540,480 bytes / 53,790 sectors**; SHA-256:
`e769228f2e1262220297bfa98b8f2841688849ab4c49ad9cd48d0d73d0a99553`.

На физической карте нужен **raw RK image с SD LBA 0**, не файл в FAT и не
автоматически найденный partition. Поддерживаются SDHC/SDXC, не SDSC/MMC.
uROM после питания/reset сама читает LBA 0 и 1 в guest FRAM, проверяет
результат RH, выставляет RH0 boot ABI и запускает PC=0. Гостевой `RESET`
не перечитывает диск и не стирает RAM. При отказе загрузки cause=5, guest
fetch не начинается; после исправления карты board reset пробует снова.
Обычная прошивка не печатает отдельное меню ошибки загрузки.

Изначально RT-11 зависал в memory sizing `005212..005264`: zero/ignore MMU
stubs ложно сообщали о наличии MMU. Исправлено **только в активном ASM**:
пробы отсутствующих регистров теперь bus-timeout. Это реальная найденная
ошибка. Причина раннего отдельного случая «на терминале ничего» полностью
не доказана; диагностическая загрузка сама по себе её не устанавливает.

`Unknown Processor` устранён коммитом **a985039**: MAINT[7:4]=1,
MAINT=`000020`, MFPT=5. Добавлены четыре code words, без RTL/context changes.
После прошивки пользователь подтвердил с платы:

```text
RT-11FB (S) V05.03
Booted from DM0:RT11FB
PDP 11/73A Processor
56KB of memory
Floating Point Microcode
Extended Instruction Set (EIS)
Floating Instruction Set (FIS)
Cache Memory
50 Cycle System Clock
...
FPU support
.
```

**FIS, FPA и FP11 — разные вещи.** В MAINT bit 8 (octal `000400`) — optional
FPA accelerator. Он **сброшен**, и это правильно. Этот `RESORC.SAV` при MFPT=5
и FPA=0 печатает `Floating Point Microcode`, при FPA=1 — `Floating Point
Accelerator Unit`. RT-11 предполагает встроенную floating microcode реального
J-11 по модели CPU, а не функционально проверяет наш FP11. **FP11 не реализован**;
FIS определяется отдельно. Не выставлять FPA ради косметики, не удалять FIS
и не искать ещё один бит для выключения этой строки. Disk/RESORC не патчили.
`Cache Memory` и `FPU support` тоже не доказывают наличие CPU cache/FP11.

## 8. Проверки и границы доказанного

### Полная симуляция стабильного RT-11

Mac, Verilator, логи `testbench/build/rt11-kdj11a/`:

- **8/8 checks**, 1,577,603,541 native clocks, ~578.59 host seconds.
- 232 sector reads, 6 simulated writes, 5 dirty RAM-overlay sectors.
- 43 input bytes приняты; `SHOW CONFIGURATION` и `DIRECTORY SY:RT11FB.SYS`
  заканчиваются **новым** KMON prompt.
- `RT11FB.SYS` — 103 blocks, 51455 free blocks; source-image SHA не изменён.
- Не ограничиваться наличием banner или `$finish`: runner проверяет сценарий.

Модель SD открывает backing image как **rb**, guest writes держит в volatile
overlay (до 256 dirty sectors); runner сравнивает SHA до/после, в том числе
при ошибках. **Физический RT-11 пишет реальную SD**, у него этого overlay нет.

### Diamond и физическая плата

Изолированный build stable source в `/tmp/microcpu-kdj11a-a985039.nlh9z9`
прошёл все стадии до JED, exit=0. Отдельный `FLASH Verify ID` прошёл,
затем `FLASH Erase,Program,Verify`: **19 seconds**, erase 930 ms, success.
FT2232 A, FTUSB-0, TCK delay 30; реально в логе **200000 Hz**.
Уже открытый UART на B не закрывали и не отсоединяли.

После этого пользователь сам прислал SHOW CONFIGURATION с **PDP 11/73A**,
FIS и 50-Hz clock с физической платы. Directory после **этого** JED проверен
в симуляции, но в данном hardware transcript не повторён. Более ранняя
NOFIS trace физически выполняла SHOW CONFIGURATION, DIRECTORY и SHOW ALL.
Не смешивать эти уровни/ревизии доказательств.

### Остальные регрессии

- Выбранные no-MMU DCJ11 C-core fixtures: **209 snapshots, 29 EIS cases**,
  не весь upstream suite. C-only/неподходящие состояния явно исключаются
  из RTL replay; bank initialization нормализуется только в fixture.
- FIS: **4040/4040 exact-reference cases** на независимом rational oracle;
  не полагаться только на host float C-FIS. Полная sweep была на более раннем
  арифметически идентичном коде; при a985039 прогнаны directed/fault FIS.
- Новые/старые MAINT word/byte tests, **600 absent-MMU accesses**, guest
  instructions, EA/MOVB, peripherals, RS/SP, HALT, RESET/RTT и no-FIS traps.
- Actual board-top test: UART TX `U`, RX `Z`, guest RESET, два WAIT/vector-100
  interrupts. Icarus 2,699,281 clocks. Семь cold-boot сценариев есть в обоих
  симуляторах; normal path 2,679,094 clocks. EBR-проверки — отдельные модели.
- При последних documentation commits: 11 assembler smoke + 24 profile tests,
  native Icarus/legacy board tests, ucode-native tests, SD board test,
  семь Verilator cold-boot scenarios и 14 static project checks прошли.
  Проверены 48 make targets через `-n` и ссылки. Это **не новый Diamond run**.

## 9. Команды для продолжения на Mac

Ниже запускать **из `/Users/sash/Work/FPGA/microcpu`**. Проверенные версии:
Icarus 12.0, Verilator 5.050; нужны C/C++, make, Python 3, для static Tcl
проверок — `tclsh`. `microasm11` заранее собрать в соседнем репозитории.

```sh
git status --short --branch
git log -8 --oneline
make -C asm test
python3 testbench/check_preserved_profiles.py

# Короткие проверки движка и реального board top.
make -C testbench ucode-native-test
make -C testbench -f Makefile.disk hc1200-sd-test disk-cold-boot-fast

# Активный no-disk CPU + selected reference + FIS.
make -C testbench ucode-test ucode-core-test
make -C testbench ucode-fis-reference-test FIS_JOBS=4

# Полная SD конфигурация.
make -C testbench -f Makefile.disk disk-test disk-nofis-test
make -C testbench -f Makefile.disk disk-image-test disk-no-mmu-test
make -C testbench -f Makefile.disk disk-core-test disk-fis-test FIS_JOBS=4

# Полный boot и команды через serial pins; около 10 host minutes.
make -C testbench -f Makefile.disk rt11-boot-fast \
  RT11_IMAGE=/Users/sash/Work/PROJECTS/k1801vm1/lsi11/disks/rt11v503.dsk

# Более короткая проверка двух boot sectors / entry; не весь boot.
make -C testbench -f Makefile.disk rt11-bootstrap-test

# Сохранённые original+j11 и полная профильная регрессия.
make -C testbench test
make -C testbench profile-acceptance FIS_JOBS=4
```

`make test` **не** включает active ucode/SD; `make -C testbench` без target
только компилирует original `tb.vvp`. Полный Icarus RT-11 — `rt11-boot-test`,
намного медленнее `rt11-boot-fast`. Не запускать все suite с внешним `make -j`:
shared fixture directories могут конфликтовать. Есть `FIS_JOBS` и
`VERILATOR_JOBS` для предусмотренного внутреннего параллелизма.

Переопределения при другом layout: `ASM11=/abs/.../microasm11/microasm11`,
`CORE_DIR=/abs/.../k1801vm1`, `RT11_IMAGE=/abs/.../rt11v503.dsk`.
Для EBR: `LATTICE_SIM_DIR=/path/to/diamond/cae_library/simulation/verilog/machxo2`,
в каталоге должны быть `PDPW8KC.v` и зависимости. На Mac достаточно копии
vendor models, запуска Diamond нет. Targets: `ucode-ebr-test`,
`profile-acceptance-ebr`, disk `disk-ebr-test`, `disk-cold-boot-ebr-test`.

Выходы — `testbench/build/`. `.lst` и `.asm.log` полезны при отладке;
`.words` — 16-bit packed uROM, guest `.hex` — byte addressed, не смешивать.
Полный boot пишет console.log/simulation.log/result.json в
`build/rt11-verilator` по умолчанию. `RT11_VERIFY_ARGS='--work-dir build/NAME'`
сохраняет отдельный прогон; `--trace` включает instruction trace, не VCD.
`vcd-isa_alu` относится к original testbench. `make clean` удаляет build/logs:
сначала сохраняй нужные свидетельства, не стирай принятые артефакты.

## 10. Сборка образов и правильные LDF

| Конфигурация | Подготовка | Diamond/JED | Проект |
|---|---|---|---|
| Stable SD + FIS | `make -C boards/hc1200-microcomp` | добавить `diamond` | `microcomp.ldf` |
| Native diag | `make -C boards/hc1200-microcomp diag` | `diag-diamond` | `microcomp-diag.ldf` |
| NOFIS trace | `make -C boards/hc1200-microcomp boot-trace` | `boot-trace-diamond` | `microcomp-boot-trace.ldf` |
| Сохранённый j11 | `make -C boards j11-ucode` | `j11-diamond` | `microcomp-j11.ldf` |
| ucode без диска | `make -C boards j11-v2-ucode` | `j11-v2-diamond` | `microcomp-ucode.ldf` |
| Legacy original | `make -C boards/hc1200-microcomp original` | GUI JEDEC File | `microcomp-original.ldf` |

У двух no-disk микродвижков нет SD autoboot: guest code должен уже быть во FRAM.
Legacy top — `demo`, reference — `j11_hc1200_microcomp`, no-disk ucode —
`ucode_hc1200_microcomp`, SD/diag/trace — `ucode_sd_microcomp`. Generated EBR
module не может быть top. Main JED лежит в `impl1-sdboot`, diag в `impl1-diag`,
trace в `impl1-boot-trace`; их имена и XCF не взаимозаменяемы.

Portable microcode targets работают без Diamond/SCUBA; legacy original SRAM
требует SCUBA. Root `make` тянет legacy boards и потому требует Diamond.
`boards/Makefile.disk` — compatibility include. **`disk-diamond` и
`disk-nofis-diamond` только PAR/TRACE, JED НЕ экспортируют**. Нормальный
`hc1200-microcomp diamond` делает Synthesis, Translate, Map, PAR, PARTrace,
проверяет cumulative negative slack и затем Jedecgen.

На Ubuntu, в отдельной копии исходников:

```sh
make -C boards/hc1200-microcomp diamond \
  DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
```

Makefile задаёт `LD_PRELOAD=/lib/x86_64-linux-gnu/libstdc++.so.6` для совместимости
инструментов с Ubuntu; SCUBA дополнительно получает FOUNDRY/library paths.
Не экспортировать старые bundled C++ libraries глобально. GUI/CLI
должны использовать правильный LDF/strategy, не stale netlist другой реализации.
Доказательства fit: `.mrp`, `.par`, `.twr`, `.pad`, `.bgn` и exit status;
существующий старый JED и успешный синтез ещё ничего не доказывают.

## 11. FTDI: важное последнее исправление пользователя

Раньше из README ошибочно удалили **реальный порядок первого подключения**
и написали категоричное «не выгружать ftdi_sio». Пользователь 2026-08-29
поправил это и прислал снимок удалённых строк. Порядок восстановлен в README
и [Diamond guide](diamond.md#first-connection-detect-jtag-then-restore-uart).
Не удалять снова и не путать первичное обнаружение с обычным повторным запуском.

**Первое подключение на этой установке:**

1. Закрыть FTDI terminals/прочие users модуля; **до запуска Programmer**:
   `sudo rmmod ftdi_sio`. Это затрагивает все FTDI serial ports, поэтому
   выполняется подготовленно, без force unload.
2. Запустить Programmer, Detect Cable, дождаться обнаружения FTDI JTAG.
3. Переткнуть USB. Kernel serial driver должен вернуться; если не загрузился,
   `sudo modprobe ftdi_sio`, затем проверить interfaces.
4. В корне microcpu запустить **`./ft2232d-util/ft2232d-ctl`**.
   Если утилита не собрана — заранее `make -C ft2232d-util`.
5. Проверить, что **A/interface 0 свободен для JTAG**, а **B/interface 1
   остаётся под ftdi_sio для UART**, затем открыть терминал B.

Утилита действительно вызывает `usb_detach_kernel_driver_np(..., 0)`.
Она не отсоединяет B и не переписывает EEPROM. Нужны legacy `usb.h`/`-lusb`
(libusb-0.1 development package). Она берёт **первый 0403:6010**, без выбора
по serial number: с несколькими адаптерами сначала разрешить неоднозначность.
Даже при ошибке утилита сейчас возвращает 0; проверить текст и `lsusb -t`,
а не один exit status. Этот handoff не исправляет код самой утилиты.

**Повторное использование:** если A уже свободен, а B работает, глобально
драйвер снова не выгружать. После replug kernel может захватить A — тогда
достаточно утилиты для нужного адаптера. Bus/device и ttyUSB номера меняются.

На Ubuntu устройство **VID 0403, PID 6010 (FT2232)**. Пользователь установил
`/etc/udev/rules.d/61-ftdi-jtag.rules`:

```udev
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6010", MODE="0666", GROUP="plugdev"
```

Это фактически использованное правило. В общей документации предложен более
узкий 0660+plugdev при правильном членстве в группе; реальную систему не меняли.
`udevadm control --reload-rules` само не меняет существующий device node,
нужен replug/reapply. USB node permissions и serial tty permissions — разные.
Знак `+` у `ls -l` означает наличие ACL. Недостающий `libusb-0.1.so.4` мешал
загрузке `libdvmapp.so`; libusb-1.0 нельзя заменить фиктивным symlink.

При последней успешной прошивке: A уже был unbound, B — ftdi_sio;
пользовательский `picocom -b 115200 /dev/ttyUSB1` оставался открыт. Был выбран
**HW-USBN-2B (FTDI), FTUSB-0**, ID **0x012BA043**. Старые USB paths вроде
`1-11.3` / `001/033` — исторические, не константы. Не отключай ID verification
при чтении нулей; проверяй питание, землю, JTAGENB, wiring, кабель и TCK.

`pgrcmd` берётся из отдельного Programmer path и использует `-infile XCF`,
`-logfile`, `-cabletype usb2 -portaddress FTUSB-0`. **Операция определяется
содержимым XCF**, не его именем. `FLASH Verify ID` — read-only;
`FLASH Erase,Program,Verify` заменяет flash. Команды/ограничения:
[Diamond / Programmer](diamond.md#programmer-configuration). Не повторять
прошивку без нового соответствующего запроса пользователя.

## 12. Диагностические прошивки — не потерять

### Native SD/FRAM diag

Источник `ucode/diagnostics/sd_fram.asm`; 944 native words; guest J11 не запускает.
Banner **HC1200 DIAG 115200 8N1** перед любым SD/FRAM доступом, heartbeat ALIVE.
`R` — read-only повтор; `W` — явный FRAM R/W/save/restore. SD всегда read-only.
W проверяет по 8 bytes в каждом bank: physical hex `0200..0207` и
`10200..10207`, всего 16 bytes; это не полный тест 128 KiB. Не выключать
питание во время W; faulty transport не гарантирует сохранность.

На реальной плате CMD0/8/ACMD41/CMD58 прошли, R7=000001AA, OCR=C0FF8000,
slow/fast sector0 token FE, CRC **C478/C478 PASS**. Затем пользователь получил
**FRAM R/W PASS**, **FRAM RESTORE PASS**. Лишь дамп FRAM до W не был достаточным
доказательством работоспособности. Подробности: [native diagnostics](hc1200-diagnostics.md).

### NOFIS boot trace

Источник `ucode/diagnostics/boot_trace.asm`; **J11_BOOT_TRACE + J11_DISABLE_FIS**.
Только здесь FIS временно выключен ради trace. Реальный SD->cache->guest FRAM
boot с CRC и readback; guest RT-11 может писать SD. Banner **J11 TRACE NOFIS**.
Все числовые поля trace — **hex**, не octal. Tags C/R/V/D/G — progress,
E/S — transport/bootstrap failure, X — CRC mismatch, K/M — cache/guest FRAM
readback mismatch. Cause=5 — boot stop, cause=6 — fatal FRAM readback.
После первого guest DL11 TX progress подавляется, errors остаются видны,
RX диагностика не съедает. Это не ODT. На плате было 86 R + 86 V без E/S/X/K/M,
RT-11 выполнял SHOW/DIRECTORY/SHOW ALL. [Формат и тесты](hc1200-boot-trace.md).

Команды симуляции, не прошивки:

```sh
make -C testbench -f Makefile.diag diag-test
make -C testbench -f Makefile.diag diag-smoke
make -C testbench -f Makefile.boot-trace boot-trace-test
make -C testbench -f Makefile.boot-trace boot-trace-rt11
```

## 13. Что остаётся и чего не обещать

- RK611 — рабочий subset: drive 0, READ/WRITE, WC/BA/DMA, partial writes,
  errors и IRQ; не полная аппаратная совместимость. Geometry 3 heads ×
  22 sectors, 256 words/sector, 24-bit LBA. DMA только guest RAM, не MMU/UBMAP.
- Команда диска **синхронно блокирует guest**. Длинные transfers могут привести
  к UART RX overrun и слиянию guest timer events. Независимый 50-Hz счётчик
  не гарантирует точное RT-11 время под длительной disk load.
- Normal stable firmware потребляет read CRC bytes, но **не сверяет data CRC**;
  CRC-проверка есть в диагностических вариантах. SD write timeout/status error
  не обещает rollback уже записанных данных.
- No SDSC/MMC, FAT loader, multi-drive support, полный RK611 maintenance,
  terminal ODT, MMU/split I/D, FP11, CIS. Не добавлять их без согласованного шага.
- Внешние timing margins, signal integrity и много карт/плат не проверены.
  Stable означает проверенную текущую конфигурацию, а не абсолютную conformance.

`TODO.md`, `docs/fpga-j11.md` и нижняя часть `docs/cpu-profiles.md` содержат
**исторические этапы**: старые sizes, «FIS не реализован», «SD wiring ещё
не подтверждено», «плата не прошита» могут относиться к прежнему checkpoint.
Не превращать их в текущие задачи и не отменять поздние результаты. Для текущего
состояния сначала этот handoff, stable hardware page и latest acceptance.

Когда пользователь задаст следующий feature/bugfix: минимальный ASM/RTL diff,
directed guest ASM test, профильная проверка и size check; при необходимости
изолированный Diamond. Не расходовать последние 19 code words незаметно и
не изменять stable binary под тем же именем. Разделять «собрано», «sim pass»,
«timing pass», «FLASH verify pass», «реальный RT-11 boot» в каждом отчёте.

## 14. Карта документации и первые действия новой сессии

- [README](../README.md) — основной legacy CPU, ссылки на три версии.
- [Legacy microcomp](hc1200-microcomp.md).
- [Сохранённый J11 CPU](fpga-j11.md) и [его hardware](hc1200-microcomp-j11.md).
- [Специализированный CPU](ucode-cpu.md) и [его stable SD hardware](hc1200-microcomp-ucode.md).
- [CPU/ISA differences и история оптимизаций](cpu-profiles.md).
- [Diamond, FTDI и Programmer](diamond.md).
- [Симуляторы и test targets](../testbench/README.md).
- [Stable JED/toolchain evidence](hc1200-sd-diamond.md).
- [RT-11 boot, no-MMU и идентификация](rt11-boot.md).
- [RK611/SD scope](rk611-sd-prototype.md), [native diag](hc1200-diagnostics.md),
  [boot trace](hc1200-boot-trace.md), [исторический TODO](../TODO.md).

Первые действия: прочитать актуальный `AGENTS.md`, сделать read-only status/log
в **microcpu**, прочитать последний запрос пользователя и выбранные документы.
Не пересобирать/прошивать просто ради «восстановления контекста», не очищать
build evidence. Предыдущая сессия завершала **документацию/FTDI correction и
handoff**, а не незавершённую реализацию новой CPU-функции. Новую сессию или
автоматизацию этот документ сам не создаёт.
