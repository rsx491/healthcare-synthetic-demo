class PrescriptionsController < ApplicationController
  def fulfill
    idempotency_key = request.headers["Idempotency-Key"]

    if idempotency_key.blank?
      return render json: {
        error: "Idempotency-Key header is required"
      }, status: :bad_request
    end

    existing_fulfillment = Fulfillment.find_by(
      idempotency_key: idempotency_key
    )

    if existing_fulfillment
      prescription = existing_fulfillment.prescription

      return render json: {
        prescription_id: prescription.id,
        status: "fulfilled",
        remaining_fills: prescription.remaining_fills,
        idempotency_key: existing_fulfillment.idempotency_key,
        replayed: true
      }, status: :ok
    end

    prescription = Prescription.find(params[:id])
    updated_rows = 0
    fulfillment = nil

    begin
      Prescription.transaction do
        updated_rows = Prescription
          .where(
            id: prescription.id,
            status: "active"
          )
          .where("remaining_fills > 0")
          .update_all("remaining_fills = remaining_fills - 1")

        if updated_rows == 1
          fulfillment = Fulfillment.create!(
            prescription: prescription,
            status: "completed",
            idempotency_key: idempotency_key
          )
        end
      end
    rescue ActiveRecord::RecordNotUnique
      fulfillment = Fulfillment.find_by!(
        idempotency_key: idempotency_key
      )

      prescription = fulfillment.prescription

      return render json: {
        prescription_id: prescription.id,
        status: "fulfilled",
        remaining_fills: prescription.remaining_fills,
        idempotency_key: fulfillment.idempotency_key,
        replayed: true
      }, status: :ok
    end

    if updated_rows.zero?
      prescription.reload

      return render json: {
        error: "Prescription is not active or has no fills remaining",
        remaining_fills: prescription.remaining_fills
      }, status: :unprocessable_entity
    end

    prescription.reload

    render json: {
      prescription_id: prescription.id,
      status: "fulfilled",
      remaining_fills: prescription.remaining_fills,
      idempotency_key: fulfillment.idempotency_key,
      replayed: false
    }, status: :ok
  end
end
