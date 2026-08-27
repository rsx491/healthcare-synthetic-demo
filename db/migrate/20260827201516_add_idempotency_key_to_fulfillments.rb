class AddIdempotencyKeyToFulfillments < ActiveRecord::Migration[8.1]
  def change
    add_column :fulfillments, :idempotency_key, :string, null: false
    add_index :fulfillments, :idempotency_key, unique: true
  end
end
