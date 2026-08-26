class AddLockVersionToPrescriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :prescriptions, :lock_version, :integer, null: false, default: 0
  end
end
