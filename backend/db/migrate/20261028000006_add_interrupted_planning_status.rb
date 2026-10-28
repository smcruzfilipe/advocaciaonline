class AddInterruptedPlanningStatus < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $guard$
      BEGIN
        IF current_user <> 'advocacia_migrator' THEN
          RAISE EXCEPTION 'Migrations require advocacia_migrator, never the web or planner role';
        END IF;
      END $guard$;
    SQL

    remove_check_constraint :collection_runs, name: "collection_run_status"
    add_check_constraint :collection_runs,
      "status IN ('planned', 'no_work', 'planning_failed', 'interrupted')", name: "collection_run_status"
  end

  def down
    # Validation refuses rollback if interrupted history exists; never rewrite that history.
    remove_check_constraint :collection_runs, name: "collection_run_status"
    add_check_constraint :collection_runs,
      "status IN ('planned', 'no_work', 'planning_failed')", name: "collection_run_status"
  end
end
