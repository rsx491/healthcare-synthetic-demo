class CreateFulfillments < ActiveRecord::Migration[8.1]
  def change
    create_table :fulfillments do |t|
      t.references :prescription, null: false, foreign_key: true
      t.string :status

      t.timestamps
    end
  end
end
