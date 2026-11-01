require "minitest/autorun"
require "open3"
require "rbconfig"

class WorkerEntryTest < Minitest::Test
  def test_missing_database_url_fails_without_running_worker
    stdout, stderr, status = invoke([], { "PROCESSADOR_DATABASE_URL" => nil })
    refute status.success?
    assert_empty stdout
    assert_includes stderr, "PROCESSADOR_DATABASE_URL"
  end

  def test_date_override_is_not_a_public_argument
    stdout, stderr, status = invoke(["--date", "2026-10-22"])
    refute status.success?
    assert_empty stdout
    assert_includes stderr, "usage: processador"
  end

  def test_invalid_job_identifier_is_rejected_before_connecting
    stdout, stderr, status = invoke(["not-a-uuid"])
    refute status.success?
    assert_empty stdout
    assert_includes stderr, "usage: processador"
  end

  private

  def invoke(arguments = [], environment = {})
    Open3.capture3(environment, RbConfig.ruby, File.expand_path("../bin/processador", __dir__), *arguments)
  end
end
