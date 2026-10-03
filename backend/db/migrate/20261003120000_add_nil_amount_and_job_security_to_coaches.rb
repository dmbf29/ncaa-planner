class AddNilAmountAndJobSecurityToCoaches < ActiveRecord::Migration[8.0]
  def change
    add_column :coaches, :nil_amount, :integer
    add_column :coaches, :job_security, :integer
  end
end
