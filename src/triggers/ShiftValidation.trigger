trigger ShiftValidation on Shift (before insert, before update) {
    List<Shift> shifts = Trigger.new;

    Set<String> sr = new Set<String>();
    for(Shift shift: shifts) {
        sr.add(shift.ServiceResourceId);
    }
    
    List<ServiceResource> extendedSr = [SELECT Id FROM ServiceResource WHERE  OvertimeEnabled__c = False AND Id IN :sr];
    
    Set<String> srIds = new Set<String>();
    for(ServiceResource sr1: extendedSr) {
        srIds.add(sr1.Id);
    }
    
    Set<Shift> confirmedShifts = new Set<Shift>();
    Set<String> territoryIds = new Set<String>();
    //We will only run this validation for Shifts with Status Category = "Confirmed" AND Service Resource can work extended hours
    for(Shift shift: shifts) {
        if(shift.StatusCategory == 'Confirmed' && srIds.contains(shift.ServiceResourceId)) {
            confirmedShifts.add(shift);
            territoryIds.add(shift.ServiceTerritoryId);
        }
    }

    if(confirmedShifts.size() > 0) {
        //Get all Service Territory IDs along with their OperatingHourId
        ServiceTerritory[] territoryIdsWithOperatingHours = [SELECT Id, OperatingHoursId FROM ServiceTerritory WHERE Id IN :territoryIds];

        Set<String> operatingHourIds = new Set<String>();
        for(ServiceTerritory st: territoryIdsWithOperatingHours) {
            //Service Territory may not have Operating Hour defined
            if(st.OperatingHoursId != null) {
                operatingHourIds.add(st.OperatingHoursId);
            }
        }

        //Get Timeslot information for all Operating Hours got in previous step. We disregard all STM level concurrent timeslots (Shifts with MaxAppointments set to 1)
        TimeSlot[] timeSlots = [SELECT Id, DayOfWeek, StartTime, EndTime, OperatingHoursId FROM TimeSlot WHERE MaxAppointments = 1 AND OperatingHoursId IN :operatingHourIds];

        //Complex data structure to store Working hours for all Service territories. We will store empty inner map in case Service Territory does not have Operating Hour defined
        Map<String, Map<String, TimeSlot>> serviceTerritoryWithTimeSlotsPerDay = new Map<String, Map<String, TimeSlot>>();

        for(ServiceTerritory territory: territoryIdsWithOperatingHours) {
            Map<String, TimeSlot> timeSlotsPerDay = new Map<String, TimeSlot>();

            for(TimeSlot timeSlot: timeSlots) {
                if(timeslot.OperatingHoursId == territory.OperatingHoursId) {
                    timeSlotsPerDay.put(TimeSlot.DayOfWeek.substring(0,3), TimeSlot);
                }
            }
            serviceTerritoryWithTimeSlotsPerDay.put(territory.Id, timeSlotsPerDay);
        }

        //Main validation logic for all confirmed shifts
        for(Shift s: confirmedShifts) {
            String dayOfShiftStart = ((Datetime) s.StartTime).format('E').substring(0,3);
            String dayOfShiftEnd = ((Datetime) s.EndTime).format('E').substring(0,3);

            Map<String, TimeSlot> slots = serviceTerritoryWithTimeSlotsPerDay.get(s.ServiceTerritoryId);

            if(dayOfShiftStart != dayOfShiftEnd) {
                s.addError('Shift should be within Service Territory\'s Operating hours ');
            } else if(slots.get(dayOfShiftStart) == null || slots.get(dayOfShiftEnd) == null) {
                s.addError('Operating Hours for Service Territory not set up correctly');
            }else if(s.StartTime.time() < slots.get(dayOfShiftStart).StartTime || s.EndTime.time() > slots.get(dayOfShiftEnd).EndTime) {
                //Eureka
                s.addError('Shift should be within Service Territory\'s Operating hours ');
            }
        }
    }
}