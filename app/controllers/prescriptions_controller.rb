class PrescriptionsController < ApplicationController
  def fulfill
    prescription = Prescription.find(params[:id])

    unless prescription.status == "active"
      return render json: { error: "Prescription is not active" }, status: :unprocessable_entity
    end

    unless prescription.remaining_fills > 0
      return render json: { error: "No fills remaining" }, status: :unprocessable_entity
    end

    # Deliberately widen the race-condition window for the demo
    sleep 0.25

    Prescription.transaction do
      Fulfillment.create!(
        prescription: prescription,
        status: "completed"
      )

      prescription.update!(
        remaining_fills: prescription.remaining_fills - 1
      )
    end

    render json: {
      prescription_id: prescription.id,
      status: "fulfilled",
      remaining_fills: prescription.remaining_fills
    }, status: :ok
  end
end