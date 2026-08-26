class PrescriptionsController < ApplicationController
  def fulfill
    prescription = Prescription.find(params[:id])

    unless prescription.status == "active"
      return render json: { error: "Prescription is not active" }, status: :unprocessable_entity
    end

    unless prescription.remaining_fills > 0
      return render json: { error: "No fills remaining" }, status: :unprocessable_entity
    end

    begin
      Prescription.transaction do
        Fulfillment.create!(
          prescription: prescription,
          status: "completed"
        )

        prescription.update!(
          remaining_fills: prescription.remaining_fills - 1
        )
      end
    rescue ActiveRecord::StaleObjectError
      prescription.reload

      return render json: {
        error: "Prescription changed during fulfillment",
        remaining_fills: prescription.remaining_fills
      }, status: :conflict
    end

    render json: {
      prescription_id: prescription.id,
      status: "fulfilled",
      remaining_fills: prescription.remaining_fills,
      lock_version: prescription.lock_version
    }, status: :ok
  end
end
