/*
Copyright 2017-2019 VMware, Inc.
SPDX-License-Identifier: BSD-2-Clause
*/
package com.vmware.weathervane.auction.data.repository.event;

import static com.datastax.driver.core.querybuilder.QueryBuilder.in;
import static com.datastax.driver.core.querybuilder.QueryBuilder.delete;
import static com.datastax.driver.core.querybuilder.QueryBuilder.eq;
import static com.datastax.driver.core.querybuilder.QueryBuilder.set;
import static com.datastax.driver.core.querybuilder.QueryBuilder.update;

import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.function.Consumer;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.cassandra.core.CassandraOperations;

import com.datastax.driver.core.querybuilder.BuiltStatement;
import com.vmware.weathervane.auction.data.model.AttendanceRecord;
import com.vmware.weathervane.auction.data.model.AttendanceRecord.AttendanceRecordState;

public class AttendanceRecordRepositoryImpl implements AttendanceRecordRepositoryCustom {

	private DateFormat dateFormat; 
	public AttendanceRecordRepositoryImpl() {
		super();

		String datePattern = "yyyy-MM-dd";
		dateFormat = new SimpleDateFormat(datePattern); 
	}

	@Autowired
	@Qualifier("cassandraEventTemplate")
	CassandraOperations cassandraOperations;
	
	@Override
	public void leaveAuctionsForUser(Long userId) {
		List<Date> recordTimes = 
				cassandraOperations.select("select record_time from attendancerecord_by_userid WHERE user_id = " + userId + ";", Date.class);
		BuiltStatement update = update("attendancerecord_by_userid")
				.with(set("state", AttendanceRecordState.LEFT.toString()))
				.where(eq("user_id", userId)).and(in("record_time", recordTimes));
		cassandraOperations.execute(update);

	}

	@Override
	public void deleteByAuctionId(Long auctionId) {
		
		List<Long> userIds = 
				cassandraOperations.select("select user_id from attendancerecord_by_userid WHERE auction_id = " + auctionId + ";", Long.class);
		
		userIds.parallelStream().forEach(
				new Consumer<Long>() {

					@Override
					public void accept(Long t) {
						BuiltStatement delete = delete().from("attendancerecord_by_userid").where(eq("user_id", t));
						cassandraOperations.execute(delete);						
					}
				});
	}

	@Override
	public List<AttendanceRecord> findByUserId(Long userId) {
		String selectString = "select * from attendancerecord_by_userid where user_id = " + userId;
		return cassandraOperations.select(selectString, AttendanceRecord.class);
	}

	@Override
	public List<AttendanceRecord> findByUserIdAndTimestampLessThanEqual(Long userId, Date toDate) {
		String selectString = "select * from attendancerecord_by_userid where user_id = " + userId;
		selectString += " and record_time <= " + dateFormat.format(toDate);
		return cassandraOperations.select(selectString, AttendanceRecord.class);
	}

	@Override
	public List<AttendanceRecord> findByUserIdAndTimestampGreaterThanEqual(Long userId, Date fromDate) {
		String selectString = "select * from attendancerecord_by_userid where user_id = " + userId;
		selectString += " and record_time >= " + dateFormat.format(fromDate);
		return cassandraOperations.select(selectString, AttendanceRecord.class);
	}

	@Override
	public List<AttendanceRecord> findByUserIdAndTimestampBetween(Long userId, Date fromDate, Date toDate) {
		String selectString = "select * from attendancerecord_by_userid where user_id = " + userId;
		selectString += " and record_time <= " + dateFormat.format(toDate);
		selectString += " and record_time >= " + dateFormat.format(fromDate);
		return cassandraOperations.select(selectString, AttendanceRecord.class);
	}

}
