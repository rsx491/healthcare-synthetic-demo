class CreatePrescriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :prescriptions do |t|
      t.string :drug_name, null: false
      t.string :status, null: false, default: "active"
      t.integer :remaining_fills, null: false, default: 0

      t.timestamps
    end
  end
end