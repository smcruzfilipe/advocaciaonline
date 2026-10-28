require "test_helper"

class DatabaseContextTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    assert_equal "advocacia_runtime", ApplicationRecord.connection.select_value("SELECT current_user")
    @token_a, = authenticated_session
    @token_b, = authenticated_session
    @lawyer_a = LawyerOnboarding.call(token: @token_a, input: profile_payload)
    @lawyer_b = LawyerOnboarding.call(token: @token_b, input: profile_payload.merge("full_name" => "Bruno Lima"))
    assert_equal [], Lawyer.pluck(:id)
  end

  test "nested session B restores session A immediately after successful return" do
    DatabaseContext.with_session(@token_a) do
      assert_equal [@lawyer_a.id], Lawyer.pluck(:id)
      DatabaseContext.with_session(@token_b) do
        assert_equal [@lawyer_b.id], Lawyer.pluck(:id)
      end
      assert_equal [@lawyer_a.id], Lawyer.pluck(:id)
    end
    assert_equal [], Lawyer.pluck(:id)
  end

  test "nested session B restores session A when its block raises" do
    DatabaseContext.with_session(@token_a) do
      assert_equal [@lawyer_a.id], Lawyer.pluck(:id)
      assert_raises(RuntimeError) do
        DatabaseContext.with_session(@token_b) do
          assert_equal [@lawyer_b.id], Lawyer.pluck(:id)
          raise "inner transaction failed"
        end
      end
      assert_equal [@lawyer_a.id], Lawyer.pluck(:id)
    end
    assert_equal [], Lawyer.pluck(:id)
  end

  test "session context does not escape into an existing outer transaction" do
    ApplicationRecord.transaction do
      assert_equal [], Lawyer.pluck(:id)
      DatabaseContext.with_session(@token_a) do
        assert_equal [@lawyer_a.id], Lawyer.pluck(:id)
      end
      assert_equal [], Lawyer.pluck(:id)
      DatabaseContext.with_session(@token_b) do
        assert_equal [@lawyer_b.id], Lawyer.pluck(:id)
      end
      assert_equal [], Lawyer.pluck(:id)
    end
    assert_equal [], Lawyer.pluck(:id)
  end

  test "error paths do not leave session context in an outer transaction or reused connection" do
    ApplicationRecord.transaction do
      assert_equal [], Lawyer.pluck(:id)
      assert_raises(RuntimeError) do
        DatabaseContext.with_session(@token_a) do
          assert_equal [@lawyer_a.id], Lawyer.pluck(:id)
          raise "session work failed"
        end
      end
      assert_equal [], Lawyer.pluck(:id)
    end
    assert_equal [], Lawyer.pluck(:id)

    assert_raises(RuntimeError) do
      ApplicationRecord.transaction do
        DatabaseContext.with_session(@token_b) do
          assert_equal [@lawyer_b.id], Lawyer.pluck(:id)
        end
        raise "outer transaction failed"
      end
    end
    assert_equal [], Lawyer.pluck(:id)
  end

  test "onboarding inside an outer transaction commits a complete profile without leaking context" do
    token, = authenticated_session
    lawyer_id = nil
    ApplicationRecord.transaction do
      lawyer = LawyerOnboarding.call(token: token, input: profile_payload)
      lawyer_id = lawyer.id
      assert_equal [], Lawyer.pluck(:id)
    end
    assert_equal [], Lawyer.pluck(:id)
    DatabaseContext.with_session(token) do
      assert_equal [lawyer_id], Lawyer.pluck(:id)
      assert_equal 2, OabRegistration.count
      assert_equal 1, OabRegistration.where(primary: true).count
    end
  end

  test "nested onboarding for two sessions preserves both profiles and deferred checks at outer commit" do
    token_a, = authenticated_session
    token_b, = authenticated_session
    lawyer_a = nil
    lawyer_b = nil
    ApplicationRecord.transaction do
      DatabaseContext.with_session(token_a) do
        lawyer_a = LawyerOnboarding.call(token: token_a, input: profile_payload)
        DatabaseContext.with_session(token_b) do
          lawyer_b = LawyerOnboarding.call(token: token_b, input: profile_payload.merge("full_name" => "Carla Souza"))
          assert_equal [lawyer_b.id], Lawyer.pluck(:id)
        end
        assert_equal [lawyer_a.id], Lawyer.pluck(:id)
      end
      assert_equal [], Lawyer.pluck(:id)
    end
    DatabaseContext.with_session(token_a) do
      assert_equal [lawyer_a.id], Lawyer.pluck(:id)
      assert_equal 1, OabRegistration.where(primary: true).count
    end
    DatabaseContext.with_session(token_b) do
      assert_equal [lawyer_b.id], Lawyer.pluck(:id)
      assert_equal 1, OabRegistration.where(primary: true).count
    end
    assert_equal [], Lawyer.pluck(:id)
  end
end
