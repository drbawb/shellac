use failure::Fail;
use std::io;

#[derive(Debug, Fail)]
pub enum InternalError {
	#[fail(display = "internal io error: {}", inner)]
	IoError { inner: io::Error },

	#[fail(display = "fail serializing payload: {}", inner)]
	SerializerError { inner: rmp_serde::encode::Error },

	#[fail(display = "fail serializing payload: {}", inner)]
	DeserializerError { inner: rmp_serde::decode::Error },

	#[fail(display = "channel transmit error; internal channel closed?")]
	ChannelSendError,

	#[fail(display = "unknown packet type: {}", ty)]
	UnknownType { ty: u8 },
}

impl From<io::Error> for InternalError {
	fn from(error: io::Error) -> Self {
		InternalError::IoError { inner: error }
	}
}

impl From<rmp_serde::encode::Error> for InternalError {
	fn from(error: rmp_serde::encode::Error) -> Self {
		InternalError::SerializerError { inner: error }
	}
}

impl From<rmp_serde::decode::Error> for InternalError {
	fn from(error: rmp_serde::decode::Error) -> Self {
		InternalError::DeserializerError { inner: error }
	}
}
