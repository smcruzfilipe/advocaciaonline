require "date"
require "time"
require "minitest/autorun"
require_relative "../../despachante/collection_schedule"

class CollectionScheduleTest < Minitest::Test
  LOCAL_DATE = Date.new(2026, 10, 28)
  FIRST_SLOT = { slot: 1, date: LOCAL_DATE, scheduled_at: Time.utc(2026, 10, 28, 7) }.freeze
  SECOND_SLOT = { slot: 2, date: LOCAL_DATE, scheduled_at: Time.utc(2026, 10, 28, 19) }.freeze

  def setup
    @schedule = CollectionSchedule.new(first: "04:00", second: "16:00")
  end

  def test_requires_both_explicit_times_without_defaults
    assert_raises(ArgumentError) { CollectionSchedule.new }
    assert_raises(ArgumentError) { CollectionSchedule.new(first: "04:00") }
    assert_raises(ArgumentError) { CollectionSchedule.new(second: "16:00") }
  end

  def test_rejects_absent_or_non_string_times_in_either_slot
    [nil, false, 400, 4.0, :"04:00", [], {}].each do |value|
      assert_raises(ArgumentError, "first must reject #{value.inspect}") do
        CollectionSchedule.new(first: value, second: "16:00")
      end
      assert_raises(ArgumentError, "second must reject #{value.inspect}") do
        CollectionSchedule.new(first: "04:00", second: value)
      end
    end
  end

  def test_rejects_anything_other_than_strict_ascii_hh_mm_in_either_slot
    [
      ["", ""],
      [" ", " "],
      ["4:00", "6:00"],
      ["04:0", "16:0"],
      ["004:00", "016:00"],
      ["04:000", "16:000"],
      ["04:00:00", "16:00:00"],
      ["04:00Z", "16:00Z"],
      [" 04:00", " 16:00"],
      ["04:00 ", "16:00 "],
      ["04:00\n", "16:00\n"],
      ["04:00\r\n", "16:00\r\n"],
      ["04:00\0", "16:00\0"],
      ["04：00", "16：00"],
      ["０４:００", "１６:００"],
      ["+04:00", "+16:00"],
      ["-04:00", "-16:00"]
    ].each do |first, second|
      assert_raises(ArgumentError, "first must reject #{first.inspect}") do
        CollectionSchedule.new(first: first, second: "16:00")
      end
      assert_raises(ArgumentError, "second must reject #{second.inspect}") do
        CollectionSchedule.new(first: "04:00", second: second)
      end
    end
  end

  def test_rejects_hours_and_minutes_outside_the_twenty_four_hour_clock
    %w[24:00 25:00 23:60 04:60 99:99].each do |value|
      assert_raises(ArgumentError, "first must reject #{value.inspect}") do
        CollectionSchedule.new(first: value, second: "23:59")
      end
      assert_raises(ArgumentError, "second must reject #{value.inspect}") do
        CollectionSchedule.new(first: "04:00", second: value)
      end
    end
  end

  def test_rejects_first_slot_before_four_in_the_morning
    %w[00:00 00:01 03:59].each do |first|
      assert_raises(ArgumentError, "first must reject #{first}") do
        CollectionSchedule.new(first: first, second: "16:00")
      end
    end
  end

  def test_rejects_identical_times
    %w[04:00 16:00 23:59].each do |time|
      assert_raises(ArgumentError) { CollectionSchedule.new(first: time, second: time) }
    end
  end

  def test_rejects_times_that_are_not_in_ascending_order
    [["16:00", "04:00"], ["04:01", "04:00"], ["23:59", "23:58"]].each do |first, second|
      assert_raises(ArgumentError) { CollectionSchedule.new(first: first, second: second) }
    end
  end

  def test_nothing_is_due_immediately_before_the_first_slot
    now = Time.iso8601("2026-10-28T03:59:59.999999-03:00")

    assert_equal [], @schedule.due(now: now)
  end

  def test_first_slot_is_due_at_its_exact_scheduled_instant
    now = Time.iso8601("2026-10-28T04:00:00-03:00")

    assert_equal [FIRST_SLOT], @schedule.due(now: now)
  end

  def test_only_first_slot_is_due_immediately_after_the_first_slot
    now = Time.iso8601("2026-10-28T04:00:00.000001-03:00")

    assert_equal [FIRST_SLOT], @schedule.due(now: now)
  end

  def test_only_first_slot_is_due_immediately_before_the_second_slot
    now = Time.iso8601("2026-10-28T15:59:59.999999-03:00")

    assert_equal [FIRST_SLOT], @schedule.due(now: now)
  end

  def test_both_slots_are_due_in_order_at_the_second_scheduled_instant
    now = Time.iso8601("2026-10-28T16:00:00-03:00")

    assert_equal [FIRST_SLOT, SECOND_SLOT], @schedule.due(now: now)
  end

  def test_both_slots_remain_due_immediately_after_the_second_slot
    now = Time.iso8601("2026-10-28T16:00:00.000001-03:00")

    assert_equal [FIRST_SLOT, SECOND_SLOT], @schedule.due(now: now)
  end

  def test_a_late_start_returns_only_the_two_current_day_slots_in_order
    now = Time.iso8601("2026-10-28T23:59:59.999999-03:00")

    assert_equal [FIRST_SLOT, SECOND_SLOT], @schedule.due(now: now)
  end

  def test_utc_and_brasilia_representations_of_the_same_instant_have_the_same_due_slots
    utc = Time.utc(2026, 10, 28, 7)
    brasilia = Time.iso8601("2026-10-28T04:00:00-03:00")

    assert_equal [FIRST_SLOT], @schedule.due(now: utc)
    assert_equal [FIRST_SLOT], @schedule.due(now: brasilia)
  end

  def test_the_input_offset_does_not_replace_the_sao_paulo_time_zone
    now = Time.iso8601("2026-10-29T04:00:00+09:00")

    assert_equal [FIRST_SLOT, SECOND_SLOT], @schedule.due(now: now)
  end

  def test_utc_midnight_still_returns_slots_for_the_previous_local_date
    now = Time.utc(2026, 10, 29, 0)

    assert_equal [FIRST_SLOT, SECOND_SLOT], @schedule.due(now: now)
  end

  def test_the_last_instant_before_local_midnight_keeps_the_local_date
    now = Time.iso8601("2026-10-29T02:59:59.999999Z")

    assert_equal [FIRST_SLOT, SECOND_SLOT], @schedule.due(now: now)
  end

  def test_local_midnight_does_not_recover_previous_day_slots
    assert_equal [FIRST_SLOT, SECOND_SLOT], @schedule.due(now: Time.utc(2026, 10, 29, 2, 59, 59))
    assert_equal [], @schedule.due(now: Time.utc(2026, 10, 29, 3))
    assert_equal [], @schedule.due(now: Time.utc(2026, 10, 29, 6, 59, 59))
  end

  def test_the_next_day_starts_with_its_own_first_slot_without_previous_day_slots
    assert_equal [FIRST_SLOT, SECOND_SLOT], @schedule.due(now: Time.utc(2026, 10, 28, 19))
    assert_equal [
      { slot: 1, date: Date.new(2026, 10, 29), scheduled_at: Time.utc(2026, 10, 29, 7) }
    ], @schedule.due(now: Time.utc(2026, 10, 29, 7))
  end

  def test_year_changes_follow_the_local_date_instead_of_the_utc_date
    assert_equal [
      { slot: 1, date: Date.new(2026, 12, 31), scheduled_at: Time.utc(2026, 12, 31, 7) },
      { slot: 2, date: Date.new(2026, 12, 31), scheduled_at: Time.utc(2026, 12, 31, 19) }
    ], @schedule.due(now: Time.utc(2027, 1, 1, 2, 59, 59))
    assert_equal [], @schedule.due(now: Time.utc(2027, 1, 1, 3))
  end

  def test_four_am_is_valid_and_slots_may_be_one_minute_apart
    schedule = CollectionSchedule.new(first: "04:00", second: "04:01")

    assert_equal [
      { slot: 1, date: LOCAL_DATE, scheduled_at: Time.utc(2026, 10, 28, 7) }
    ], schedule.due(now: Time.utc(2026, 10, 28, 7, 0, 59))
    assert_equal [
      { slot: 1, date: LOCAL_DATE, scheduled_at: Time.utc(2026, 10, 28, 7) },
      { slot: 2, date: LOCAL_DATE, scheduled_at: Time.utc(2026, 10, 28, 7, 1) }
    ], schedule.due(now: Time.utc(2026, 10, 28, 7, 1))
  end

  def test_twenty_three_fifty_nine_is_a_valid_last_slot_on_its_local_date
    schedule = CollectionSchedule.new(first: "23:58", second: "23:59")
    first = { slot: 1, date: LOCAL_DATE, scheduled_at: Time.utc(2026, 10, 29, 2, 58) }
    second = { slot: 2, date: LOCAL_DATE, scheduled_at: Time.utc(2026, 10, 29, 2, 59) }

    assert_equal [first], schedule.due(now: Time.utc(2026, 10, 29, 2, 58, 59))
    assert_equal [first, second], schedule.due(now: Time.utc(2026, 10, 29, 2, 59))
    assert_equal [], schedule.due(now: Time.utc(2026, 10, 29, 3))
  end

  def test_configured_minutes_are_preserved_in_the_absolute_scheduled_times
    schedule = CollectionSchedule.new(first: "04:07", second: "16:32")
    first = { slot: 1, date: LOCAL_DATE, scheduled_at: Time.utc(2026, 10, 28, 7, 7) }
    second = { slot: 2, date: LOCAL_DATE, scheduled_at: Time.utc(2026, 10, 28, 19, 32) }

    assert_equal [], schedule.due(now: Time.utc(2026, 10, 28, 7, 6, 59))
    assert_equal [first], schedule.due(now: Time.utc(2026, 10, 28, 7, 7))
    assert_equal [first], schedule.due(now: Time.utc(2026, 10, 28, 19, 31, 59))
    assert_equal [first, second], schedule.due(now: Time.utc(2026, 10, 28, 19, 32))
  end

  def test_sao_paulo_uses_its_historical_daylight_saving_offset_not_a_fixed_minus_three
    first = { slot: 1, date: Date.new(2018, 12, 1), scheduled_at: Time.utc(2018, 12, 1, 6) }
    second = { slot: 2, date: Date.new(2018, 12, 1), scheduled_at: Time.utc(2018, 12, 1, 18) }

    assert_equal [], @schedule.due(now: Time.utc(2018, 12, 1, 5, 59, 59))
    assert_equal [first], @schedule.due(now: Time.utc(2018, 12, 1, 6))
    assert_equal [first, second], @schedule.due(now: Time.utc(2018, 12, 1, 18))
  end

  def test_due_is_a_repeatable_calculation_not_an_in_memory_execution_claim
    now = Time.utc(2026, 10, 28, 19)

    assert_equal [FIRST_SLOT, SECOND_SLOT], @schedule.due(now: now)
    assert_equal [FIRST_SLOT, SECOND_SLOT], @schedule.due(now: now)
  end
end
