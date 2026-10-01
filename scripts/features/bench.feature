Feature: Native performance benchmarks
  `ci.mbtx bench` builds the native release, samples each benchmark workload
  and the peak RSS of `ion print -`, and compares the medians with the newest
  earlier successful main run. Timing and memory changes are informational:
  only a failed measurement fails the run.

  Scenario: The options have defaults
    When I parse the bench arguments ""
    Then the bench options are:
      | output_dir         | items | samples | sample_ms | cli_items |
      | _build/performance | 5000  | 5       | 100       | 300000    |

  Scenario: The options can be given
    When I parse the bench arguments "--samples 1 --items 500 --cli-items 1000 --sample-ms 20 --output-dir out"
    Then the bench options are:
      | output_dir | items | samples | sample_ms | cli_items |
      | out        | 500   | 1       | 20        | 1000      |

  Scenario Outline: Bad bench arguments are rejected
    When I parse the bench arguments "<arguments>"
    Then the bench arguments are rejected with "<message>"

    Examples:
      | arguments         | message                                           |
      | --items 0         | bench: sample and workload sizes must be positive |
      | --samples -1      | bench: sample and workload sizes must be positive |
      | --sample-ms 0     | bench: sample and workload sizes must be positive |
      | --cli-items 0     | bench: sample and workload sizes must be positive |
      | --items many      | bench: --items must be an integer: many           |
      | --items           | bench: --items needs a value                      |
      | --verbose         | bench: unknown argument --verbose                 |

  Scenario: Each workload runs the benchmark driver of the release build
    When I parse the bench arguments "--items 500 --sample-ms 20"
    Then the workloads are:
      """
      many/read-text-sync
      many/read-text-stream
      many/read-binary-sync
      many/read-binary-stream
      many/write-text-sync
      many/write-text-stream
      many/write-binary-sync
      many/write-binary-stream
      many/hash
      large/read-text-sync
      large/read-text-stream
      large/read-binary-sync
      large/read-binary-stream
      large/write-text-sync
      large/write-text-stream
      large/write-binary-sync
      large/write-binary-stream
      large/hash
      large/write-text-incremental
      large/write-binary-incremental
      """
    And the driver command of "large/hash" is "_build/native/release/build/benchmarks/benchmarks.exe hash large 500 20"

  Scenario: A sample takes the median time per iteration
    Given the benchmark samples:
      | iterations | elapsed_ms | input_bytes | checksum |
      | 10         | 10         | 1048576     | 20       |
      | 10         | 20         | 1048576     | 20       |
      | 10         | 1000       | 1048576     | 20       |
    When I summarize the samples
    Then the median is 2.000 ms at 500.00 MiB/s
    And the metric keeps the 3 samples

  Scenario: Output that changes between samples is an error
    Given the benchmark samples:
      | iterations | elapsed_ms | input_bytes | checksum |
      | 10         | 10         | 1024        | 20       |
      | 10         | 20         | 1024        | 0        |
    When I summarize the samples
    Then the summary fails with "benchmark output changed between samples"

  Scenario: A changed input size is an error
    Given the benchmark samples:
      | iterations | elapsed_ms | input_bytes | checksum |
      | 10         | 10         | 1024        | 20       |
      | 10         | 20         | 2048        | 20       |
    When I summarize the samples
    Then the summary fails with "benchmark output changed between samples"

  Scenario Outline: An invalid measurement is an error
    Given the benchmark samples:
      | iterations   | elapsed_ms   | input_bytes   | checksum |
      | <iterations> | <elapsed_ms> | <input_bytes> | 20       |
    When I summarize the samples
    Then the summary fails with "benchmark returned invalid measurements"

    Examples:
      | iterations | elapsed_ms | input_bytes |
      | 0          | 1          | 10          |
      | 1          | 0          | 10          |
      | 1          | 1          | 0           |
      | "many"     | 1          | 10          |

  Scenario: No samples is an error
    Given the benchmark samples:
      | iterations | elapsed_ms | input_bytes | checksum |
    When I summarize the samples
    Then the summary fails with "benchmark returned invalid measurements"

  Scenario: The CLI input repeats one struct per line
    Then the CLI input for 3 items has 138 bytes and starts with:
      """
      {name: "ion", values: [1, 2, 3], tag: sample}
      {name: "ion", values: [1, 2, 3], tag: sample}
      """

  Scenario: The system time command measures the peak RSS of the CLI
    Then the timed command on Darwin is "/usr/bin/time -l ion.exe print -"
    And the timed command on Linux is "/usr/bin/time -f %M -o rss ion.exe print -"

  Scenario: The BSD time output gives the peak RSS in bytes
    Then the Darwin peak RSS of this output is 1458176 bytes:
      """
              0.01 real         0.00 user         0.00 sys
                   1458176  maximum resident set size
                         0  average shared memory size
      """

  Scenario: BSD time output without the peak RSS gives no value
    Then the Darwin peak RSS of this output is unknown:
      """
              0.01 real         0.00 user         0.00 sys
      """

  Scenario Outline: The GNU time stats file gives the peak RSS in KiB
    Then the GNU peak RSS of "<stats>" is <bytes>

    Examples:
      | stats  | bytes   |
      | 2048   | 2097152 |
      | 2048\n | 2097152 |
      | x      | unknown |

  Scenario: Changes do not fail the current results
    Given the current bench report
    And the baseline bench report is the current report with:
      | toolchain | large/read-text-sync | cli peak RSS |
      | moon old  | 1.0                  | 1024.0       |
    And the baseline bench report has no metric "many/read-text-sync"
    Then the baseline bench report is compatible
    When I compare with the bench baseline of run 36900023825 at "https://example.test/run/1"
    Then the change of "large/read-text-sync" is 900.0%
    And "many/read-text-sync" has no change
    And the peak RSS change is 100.0%
    And the bench status is "passed"
    And the bench summary is:
      """
      ## Native performance

      Status: **passed**. Timing and memory changes are informational; no thresholds fail CI.

      Commit: `after`. OS: Linux; architecture: x86_64.

      Toolchain: `moon new / moonc v1 → x`.

      Workloads: {'items': 5000, 'samples': 5, 'sample_ms': 100, 'cli_items': 300000, 'rss_method': 'external-time'}. Release builds; fixture setup and warmup excluded from samples.

      Baseline: [main CI run 36900023825](https://example.test/run/1), commit `before`.

      Environment changed: `{"toolchain": {"previous": "moon old", "current": "moon new\nmoonc v1 \u2192 x"}}`. Interpret deltas with care.

      Throughput uses the serialized fixture size; Ion Hash operates on parsed values.

      | Workload / operation | Median ms | Fixture MiB/s | Change vs main |
      | --- | ---: | ---: | ---: |
      | many/read-text-sync | 0.123 | 2.67 | n/a |
      | large/read-text-sync | 10.000 | 2.00 | +900.0% |

      CLI `print -`: 14,100,000 input bytes, median 4.2 ms, median peak RSS 0.00 MiB.
      Peak RSS change vs main: +100.0%.
      RSS includes the process/runtime; input is prepared on disk and output is discarded.

      """

  Scenario: An unavailable baseline is reported as it is
    Given the current bench report
    When the bench baseline is unavailable because "No prior artifact"
    Then the bench comparison is unavailable because "No prior artifact"
    And the bench summary is:
      """
      ## Native performance

      Status: **passed**. Timing and memory changes are informational; no thresholds fail CI.

      Commit: `after`. OS: Linux; architecture: x86_64.

      Toolchain: `moon new / moonc v1 → x`.

      Workloads: {'items': 5000, 'samples': 5, 'sample_ms': 100, 'cli_items': 300000, 'rss_method': 'external-time'}. Release builds; fixture setup and warmup excluded from samples.

      Baseline unavailable: No prior artifact.

      Throughput uses the serialized fixture size; Ion Hash operates on parsed values.

      | Workload / operation | Median ms | Fixture MiB/s | Change vs main |
      | --- | ---: | ---: | ---: |
      | many/read-text-sync | 0.123 | 2.67 | n/a |
      | large/read-text-sync | 10.000 | 2.00 | n/a |

      CLI `print -`: 14,100,000 input bytes, median 4.2 ms, median peak RSS 0.00 MiB.
      RSS includes the process/runtime; input is prepared on disk and output is discarded.

      """

  Scenario: A failed measurement fails the run and has no comparison
    Given the current bench report
    When the measurements fail with "benchmark output changed between samples"
    Then the bench status is "failed"
    And the bench summary is:
      """
      ## Native performance

      Status: **failed**. Timing and memory changes are informational; no thresholds fail CI.

      Commit: `after`. OS: Linux; architecture: x86_64.

      Toolchain: `moon new / moonc v1 → x`.

      Workloads: {'items': 5000, 'samples': 5, 'sample_ms': 100, 'cli_items': 300000, 'rss_method': 'external-time'}. Release builds; fixture setup and warmup excluded from samples.

      Baseline unavailable: Current measurements failed.

      Throughput uses the serialized fixture size; Ion Hash operates on parsed values.

      | Workload / operation | Median ms | Fixture MiB/s | Change vs main |
      | --- | ---: | ---: | ---: |
      | many/read-text-sync | 0.123 | 2.67 | n/a |
      | large/read-text-sync | 10.000 | 2.00 | n/a |

      Execution error: benchmark output changed between samples
      """

  Scenario: A long error is cut to 4000 characters
    Given the current bench report
    When the measurements fail with 5000 characters of output
    Then the bench error has 4000 characters

  Scenario Outline: An incompatible baseline is rejected
    Given the current bench report
    And the baseline bench report is the current report with:
      | toolchain |
      | moon old  |
    And the baseline bench report has <key> set to <value>
    Then the baseline bench report is incompatible

    Examples:
      | key            | value                            |
      | runner_os      | "Windows"                        |
      | architecture   | "arm64"                          |
      | target         | "wasm"                           |
      | config         | {}                               |
      | status         | "failed"                         |
      | schema_version | 2                                |
      | metrics        | {"foo": {"median_ms": 0}}        |
      | metrics        | {"foo": {"median_ms": "fast"}}   |
      | metrics        | []                               |
      | cli            | null                             |
      | cli            | {"median_peak_rss_bytes": 0}     |

  Scenario: The baseline report JSON is a compatible baseline
    Given the current bench report
    Then the JSON of the current report is a compatible baseline

  Scenario Outline: Numbers are formatted like Python format specs
    Then <value> formatted with "<spec>" is "<text>"

    Examples:
      | value      | spec | text                     |
      | 0.125      | .2f  | 0.12                     |
      | 0.375      | .2f  | 0.38                     |
      | 2.675      | .2f  | 2.67                     |
      | 0.0005     | .3f  | 0.001                    |
      | 1e21       | .1f  | 1000000000000000000000.0 |
      | -0.04      | +.1f | -0.0                     |
      | 0.0        | +.1f | +0.0                     |
      | 900.0      | +.1f | +900.0                   |
      | -12.25     | +.1f | -12.2                    |
      | 1.5        | .0f  | 2                        |
      | 2.5        | .0f  | 2                        |
      | 123456.789 | .3f  | 123456.789               |
      | 5e-324     | .3f  | 0.000                    |

  Scenario Outline: Byte counts have thousands separators
    Then <count> with thousands separators is "<text>"

    Examples:
      | count    | text       |
      | 0        | 0          |
      | 999      | 999        |
      | 1000     | 1,000      |
      | 14100000 | 14,100,000 |

  Scenario: The CPU name comes from the first model name line of /proc/cpuinfo
    Then the CPU of this cpuinfo is "Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz":
      """
      processor	: 0
      vendor_id	: GenuineIntel
      model name	: Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz
      processor	: 1
      model name	: Other
      """

  Scenario: The CPU name of an ARM board comes from the Hardware line
    Then the CPU of this cpuinfo is "BCM2835":
      """
      processor	: 0
      Hardware	: BCM2835
      """

  Scenario: A cpuinfo without a CPU name gives none
    Then the cpuinfo has no CPU name:
      """
      processor	: 0
      """
