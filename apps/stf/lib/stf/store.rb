require "json"
require "pg"

module STF
  class Store
    def initialize(connection)
      @connection = connection
    end

    def next_job
      @connection.exec("SELECT * FROM app_private.stf_processor_next()").first
    end

    def claim(job_id)
      @connection.exec_params("SELECT * FROM app_private.stf_processor_claim_available($1::uuid)", [job_id]).first
    end

    def job(job_id, token)
      json("SELECT app_private.stf_processor_job($1::uuid, $2::text)::text AS result", [job_id, token])
    end

    def renew(job_id, token)
      @connection.exec_params("SELECT * FROM app_private.stf_processor_renew($1::uuid, $2::text)", [job_id, token]).first
    end

    def start(job_id, token)
      @connection.exec_params("SELECT * FROM app_private.stf_processor_start($1::uuid, $2::text)", [job_id, token])
    end

    def commit(job_id, token, processes)
      json("SELECT app_private.stf_processor_commit($1::uuid, $2::text, $3::jsonb)::text AS result", [job_id, token, JSON.generate(processes)])
    end

    def fail(job_id, token, code)
      json("SELECT app_private.stf_processor_record_failure($1::uuid, $2::text, $3::text)::text AS result", [job_id, token, code])
    end

    private

    def json(sql, params)
      JSON.parse(@connection.exec_params(sql, params).first.fetch("result"))
    end
  end
end
